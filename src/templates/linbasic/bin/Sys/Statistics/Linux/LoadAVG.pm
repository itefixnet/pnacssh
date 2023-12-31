=head1 NAME

Sys::Statistics::Linux::LoadAVG - Collect linux load average statistics.

=head1 SYNOPSIS

    use Sys::Statistics::Linux::LoadAVG;

    my $lxs  = Sys::Statistics::Linux::LoadAVG->new;
    my $stat = $lxs->get;

=head1 DESCRIPTION

Sys::Statistics::Linux::LoadAVG gathers the load average from the virtual F</proc> filesystem (procfs).

For more information read the documentation of the front-end module L<Sys::Statistics::Linux>.

=head1 LOAD AVERAGE STATISTICS

Generated by F</proc/loadavg>.

    avg_1   -  The average processor workload of the last minute.
    avg_5   -  The average processor workload of the last five minutes.
    avg_15  -  The average processor workload of the last fifteen minutes.

=head1 METHODS

=head2 new()

Call C<new()> to create a new object.

    my $lxs = Sys::Statistics::Linux::LoadAVG->new;

It's possible to set the path to the proc filesystem.

     Sys::Statistics::Linux::LoadAVG->new(
        files => {
            # This is the default
            path    => '/proc',
            loadavg => 'loadavg',
        }
    );

=head2 get()

Call C<get()> to get the statistics. C<get()> returns the statistics as a hash reference.

    my $stat = $lxs->get;

=head1 EXPORTS

No exports.

=head1 SEE ALSO

B<proc(5)>

=head1 REPORTING BUGS

Please report all bugs to <jschulz.cpan(at)bloonix.de>.

=head1 AUTHOR

Jonny Schulz <jschulz.cpan(at)bloonix.de>.

=head1 COPYRIGHT

Copyright (c) 2006, 2007 by Jonny Schulz. All rights reserved.

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut

package Sys::Statistics::Linux::LoadAVG;

use strict;
use warnings;
use Carp qw(croak);

our $VERSION = '0.08';

sub new {
    my $class = shift;
    my $opts  = ref($_[0]) ? shift : {@_};

    my %self = (
        files => {
            path    => '/proc',
            loadavg => 'loadavg',
        }
    );

    foreach my $file (keys %{ $opts->{files} }) {
        $self{files}{$file} = $opts->{files}->{$file};
    }

    return bless \%self, $class;
}

sub get {
    my $self  = shift;
    my $class = ref $self;
    my $file  = $self->{files};
    my %lavg  = ();

    my $filename = $file->{path} ? "$file->{path}/$file->{loadavg}" : $file->{loadavg};
    open my $fh, '<', $filename or croak "$class: unable to open $filename ($!)";

    ( $lavg{avg_1}
    , $lavg{avg_5}
    , $lavg{avg_15}
    ) = (split /\s+/, <$fh>)[0..2];

    close($fh);
    return \%lavg;
}

1;
