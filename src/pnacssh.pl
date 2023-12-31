#!/usr/bin/perl
##########################
#
#  pnacssh.pl - Passive Nagios Checks via SSH (http://itefix.net/pnacssh)
#
#  v1.0  - April 2015
#
#  Copyright - Itefix Consulting & Software (www.itefix.net), 
#  License: 2-sentence BSD (Freeware)

use strict;
use warnings;
use lib "./perl";

our $DEF_SSH_PORT = 22;
our $DEF_SSH_KEYSCAN = "/usr/bin/ssh-keyscan";
our $DEF_SSH_KEYGEN = "/usr/bin/ssh-keygen";
our $DEF_SSH_KEYTYPE = "rsa";
our $DEF_SSH_KEYLEN = "2048";

use File::Copy;
use File::Path qw (make_path remove_tree);
use File::Slurp qw (edit_file_lines read_file write_file append_file);
use File::Copy::Recursive qw (dircopy pathempty);
use Config::General qw (ParseConfig);
use FindBin qw ($Bin);
use Getopt::Long;

my $config_file = "$Bin/pnacssh.config";our %pnacssh_config = ParseConfig($config_file) or die "Configuration file $config_file couldn't be loaded.";

our $MONITOR_DIR = "$Bin/staging/sftpin";
our $COLLECTOR_DIR = "$Bin/staging/collector";
our $KNOWN_HOSTS = "$Bin/etc/known_hosts";
our $AUTHORIZED_KEYS = "$Bin/etc/authorized_keys";
our $init = 0;
our $config = undef;
our $collector = 0;
our $monitor = 0;
our $hostname = undef;
our $ip = undef;
our $template = undef;
our $verbose = 0;

GetOptions (
'init' => \$init,
'config:s' => \$config,
'collector' => \$collector,
'monitor' => \$monitor,
'hostname=s' => \$hostname,
'ip=s' => \$ip,
'template=s' => \$template,
'verbose' => \$verbose
) or PrintUsage();


if ($init)
{
	InitPnacssh();

} elsif ($monitor) {
	MonitorCheckResults();

} elsif (defined $config && defined $hostname && defined $template) {
	GenerateConfig();

} elsif ($collector && defined $hostname && defined $ip && defined $template) {
	GenerateCollector();
	
} else {
	PrintUsage();
}
### Functions
###
### Creates directory structures and populates known_hosts file
###
sub InitPnacssh
{
	my $monhost = $pnacssh_config {"DataCollectorHost"} or ConfigError();
	my $monport = $pnacssh_config {"DataCollectorPort"} || $DEF_SSH_PORT;
		
	# initialize etc
	if (-d "$Bin/etc")
	{
		-d "$Bin/etc.bk" && remove_tree("$Bin/etc.bk");
		move("$Bin/etc", "$Bin/etc.bk") && print STDERR "Existing etc directory is renamed to etc.bk.\n";
	} else {
		make_path("$Bin/etc");
	}
	
	# create known_hosts
	my $keyscanbin = $pnacssh_config{"SshKeyscanBin"} || $DEF_SSH_KEYSCAN;
	system("\"$keyscanbin\" -p $monport $monhost > \"$KNOWN_HOSTS\"");
	
	# create staging structure
	make_path($COLLECTOR_DIR);	make_path($MONITOR_DIR);

}

### Monitors sftpin directory, picks up .result files and submit them to Nagios
###
sub MonitorCheckResults
{
	-d $MONITOR_DIR || die "Couldn't find directory to be monitored - $MONITOR_DIR.";
	
	my $extcmdfile = "$MONITOR_DIR/extcmd.work";
	unlink $extcmdfile;
	
	# check for all .result files
	opendir (DIR, $MONITOR_DIR) or die "Cannot open $MONITOR_DIR\n";
    my @files = readdir(DIR);
    closedir(DIR);
	
	my @results = ();
	
	foreach my $file (@files) {
        next if ($file !~ /\.result$/i);
		
		push (@results, read_file("$monitor/$file")); # slurp contents
		unlink "$monitor/$file"; # done
	}
	
	my $validresults = "";
	
	foreach my $result (@results)
	{
		# allow only service and host checks
		next if not ($result =~ /^PROCESS_SERVICE_CHECK_RESULT/ || $result =~ /^PROCESS_HOST_CHECK_RESULT/);		
		$validresults .= "[" . time . "] $result"; # nagios external command format
    }
	
	write_file($extcmdfile, $validresults);
		# Time to issue external commands in a file	for bulk processing
	my $extcmdfname = $pnacssh_config {"ExternalCommandFile"} or ConfigError();
	my $extcmd = "[" . time . "] PROCESS_FILE;$extcmdfile;1"; # process file and remove it
	
	write_file($extcmdfname, $extcmd); # submit external command

}

### Generates template-based collector packages for deployment
###
sub GenerateCollector
{
	# empty target directory and copy template directory
	my $package_dir = "$COLLECTOR_DIR/$hostname-$template";
	pathempty($package_dir);
	dircopy("$Bin/templates/$template", $package_dir);
	unlink("$package_dir/template.config"); # we don't need template config in prod
	
	# copy known_hosts
	copy("$KNOWN_HOSTS","$package_dir/known_hosts") or die "copy known_hosts failed: $!";
	
	# create PKA key pair
	my $keygen_bin = $pnacssh_config {"SshKeygenBin"} || $DEF_SSH_KEYGEN;
	my $keygen_type = $pnacssh_config {"SshKeygenType"} || $DEF_SSH_KEYTYPE;
	my $keygen_length = $pnacssh_config {"SshKeygenLength"} || $DEF_SSH_KEYLEN;
	
	system("\"$keygen_bin\" -q -t $keygen_type -b $keygen_length -N '' -C $hostname -f \"$package_dir/$hostname.key\"");
	-e "$package_dir/$hostname.key" || die "Problems during key generation.";

	-e $AUTHORIZED_KEYS && edit_file_lines { $_ = '' if /$hostname/ } $AUTHORIZED_KEYS;
	
	# append public key with options
	my $public_key = "from=\"$ip\",no-agent-forwarding,no-port-forwarding,no-pty,no-user-rc,no-X11-forwarding " .
						read_file("$package_dir/$hostname.key.pub");
	append_file($AUTHORIZED_KEYS, $public_key);
	unlink "$package_dir/$hostname.key.pub";

	# Create sftp batch script
	write_file("$package_dir/pnacssh.sftp", "put $hostname-$template.result\nquit");
	
	# Create collection script
	my $config_file = "$Bin/templates/$template/template.config";
	my $lconf = Config::General->new(-ConfigFile => $config_file,  -SplitPolicy => 'equalsign');
	my %template_config = $lconf->getall;

	my $collection_script = $template_config{"PnacsshCollectorScript"} or ConfigError();
	
	my $dcport = $pnacssh_config {"DataCollectorPort"} || $DEF_SSH_PORT;
	my $dcuser = $pnacssh_config {"DataCollectorUser"} or ConfigError();
	my $dchost = $pnacssh_config {"DataCollectorHost"} or ConfigError();

	$collection_script =~ s/__HOSTNAME__/$hostname/g;
	$collection_script =~ s/__TEMPLATE__/$template/g;
	$collection_script =~ s/__PORT__/$dcport/g;
	$collection_script =~ s/__KNOWNHOSTFILE__/$KNOWN_HOSTS/g;
	$collection_script =~ s/__PRIVATEKEY__/$hostname.key/g;
	$collection_script =~ s/__USER__/$dcuser/g;
	$collection_script =~ s/__DATACOLLECTOR__/$dchost/g;
	
	my $services_script_content = "";
	my $script_name = undef;
		
	if ($collection_script =~ /set-strictmode/)	 # Powershell
	{	
		
		foreach my $lcommand (keys %{$template_config{'commands'}})
		{
			$services_script_content .=  "\t\"$lcommand\" = \"" . $template_config{'commands'}{$lcommand} . "\"\n";
		}
		$script_name = "pnacssh-collector.ps1";			
		write_file ("$package_dir/pnacssh.cmd", "\@echo off\ncd \%~dp0\npowershell -executionpolicy bypass .\\$script_name\n");
	}
	
	if ($collection_script =~ /use strict/)
	{	
		
		foreach my $lcommand (keys %{$template_config{'commands'}})
		{
			$services_script_content .=  "\t\"$lcommand\" => \"" . $template_config{'commands'}{$lcommand} . "\",\n";
		}
		$script_name = "pnacssh-collector.pl";		
		write_file ("$package_dir/pnacssh.sh", "\#!/bin/sh\nperl ./$script_name");		
	}
			# update collection script with services code
	$collection_script =~ s/__SERVICES__/$services_script_content/;
	write_file ("$package_dir/$script_name", $collection_script);

}

### Generates nagios host/service definitions for host/template selected
###
sub GenerateConfig
{
	$config = lc $config;
			my $config_file = "$Bin/templates/$template/template.config";
	my $lconf = Config::General->new(-ConfigFile => $config_file, -SplitPolicy => 'equalsign');
	my %template_config = $lconf->getall;
	
	my $template_text;
			# print Nagios host definition
	if ($config eq '' or $config eq 'all' or $config eq 'host')
	{
		$template_text = $template_config{"NagiosHostTemplate"} or ConfigError();
		$template_text =~ s/__HOSTNAME__/$hostname/g;
		print $template_text;
	}

	print "\n";
	
	# print Nagios service definitions	if ($config eq '' or $config eq 'all' or $config eq 'service')
	{
		$template_text = $template_config{"NagiosServiceTemplate"} or ConfigError();
		
		my $services_text = "";
		
		foreach my $lcommand (keys %{$template_config{'commands'}})
		{	
			my $stext = $template_text;
			$stext =~ s/__HOSTNAME__/$hostname/g;
			$stext =~ s/__COMMAND__/$lcommand/g;
			
			$services_text .= "$stext\n";;
		}
		
		print $services_text;
	}
}

### Informs about configuration problems in a very simple way
###sub ConfigError
{
	my $code = shift;
	print STDERR "Configuration problem: $code\n";
	exit 1;
}

### Produces simple usage information
###sub PrintUsage
{

	print "
pnacssh - passive nagios checks via ssh

Usage:
  init mode:    --init 
  config mode:  --config --hostname host --template template
  package mode: --package --hostname host --ip ip --template template
  monitor mode: --monitor
";
	exit 1;
}