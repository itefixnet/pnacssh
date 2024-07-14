# pnacssh - Passive Nagios Core checks via SSH

![pnacssh](doc/pnacssh.jpg)

Pnacssh is a versatile tool to set up secure passive monitoring via ssh with a few steps. As widely known, passive checks are a convenient way to gather monitoring information from hosts which somehow are not available for active checks, and SSH offers a well proven framework for secure communications. Pnacssh has following features:

* Based on monitoring templates (basic checks for Linux and Windows are included, easily extendable)
* Create Nagios host and service definitions for the selected host and template
* Create SSH keys
* Configure SSH for secure communications
* Create host-specific sftp setup for bulk transfers of monitoring results
* Customize data collector scripts (Perl/Powershell) according to templates
* Generate host-specific data collectors which can be run periodically (cron/scheduled task)
* Monitoring incoming check results and feed them to Nagios via external command interface

As described above, Pnacssh is capable to automate all steps involved in secure passive monitoring. All this functionaliy is available as a small perl script and a set of templates, making deployment and further customization an easy task.

## Requirements

*   Nagios Core compatible monitoring system
*   SSH Server
*   Perl

## Installation

Pnacssh comes as a zipped archive file. Download and unpack it to the target installation directory (**_/var/opt/pnacssh_** in examples)

## Initial setup

*   Create an ordinary dedicated user for pnacssh (_**pnacssh-user**_ in examples)

*   Update parameters in the main configuration file _pnacssh.config:_

| **Parameter**| **Description**|**Default value**|
| ------------- |:-------------:| -----:|
| **DataCollectorHost**| Nagios server's name or ip address | None. **Required**|
**DataCollectorUser**|Dedicated ordinary user for pnacssh|None. **Required**|
|**DataCollectorPort**|Listening port for SSH server|22|
|**SshKeygenBin**|Where to find ssh-keygen program|/usr/bin/ssh-keygen|
|**SshKeyscanBin**|Where to find ssh-keyscan program|/usr/bin/ssh-keyscan|
|**SshKeygenType**|SSH public key type|rsa|
|**SshKeygenLength**|SSH public key length|2048|
|**ExternalCommandFile**|Nagios external command file|/usr/local/nagios/var/rw/nagios.cmd|


*   run pnacssh in _init mode_:

**./pnacssh-pl --init**

_init mode_ will create the following directory/file structure:

**staging/collector** - collector packages will be created here

**staging/sftpin** - check results from remote hosts

**etc/known\_hosts** - Nagios host's ssh host public keys for distribution

*   Modify the home directory of _**pnacssh-user**_ to _**/var/opt/pnacssh/staging/sftpin**_ (Linux command usermod)

*   Activate a cron job to run pnacssh in monitor mode:

**\*/5 \* \* \* \* cd "/var/opt/pnacssh"; ./pnacssh.sh --monitor**

cron entry above will run pnacssh in monitor mode every 5 minutes, consolidating all arrived check results into an external command file and submit it to Nagios before deleting it.

*   Append the following directives to the _**sshd\_config**_ file (location may vary, a good guess is /etc/ssh)

**Match User _pnacssh-user_**

  **PasswordAuthentication no**

  **PubkeyAuthentication yes**

  **AllowTcpForwarding no**

  **AuthorizedKeysFile /var/opt/pnacssh/etc/authorized\_keys**

 Setup above will make sure that pnacssh-user can only use public key authentication based on managed keys in pnacssh directory. NB! read permissions only.

That's all. Your Nagios+Ssh system is now ready for processing passive checks via pnacssh.

## Basic monitoring of Linux hosts

Pnacssh comes with a standard Linux template called _linbasic_. Follow steps below to monitor a Linux system (_lindef_ (ip 10.4.5.6) in examples) via pnacssh:

* Run pnacssh in config mode to create Nagios configuration files:
```
./pnacssh.pl --config --hostname lindef --template linbasic > <nagios configuration directory>
```
pnacssh in config mode will create host and services definitions for basic Linux monitoring on _lindef_.

* Run pnacssh in collector mode to create data collector which will be deployed on host _lindef_:
```
./pnacssh.pl --collector --hostname lindef --ip 10.4.5.6 --template linbasic
```
Pnacssh in collector mode will generate a data collector for host _lindef_ ready to use. Data collector content is in _staging/collector/lindef-linbasic_ directory.

* Transfer data collector directory securely to the host lindef. **NB!** This step is important as the data collector contains the private key. You need to make sure that that key arrives its host in a secure manner. Making an encrypted zip archive can be a solution.
* Copy data collector directory contents to a dedicated directory on _lindef_ (_/var/opt/pnacssh_ for example)
* Run the data collector directly to see if it performs checks and transfer results as expected
* Set up a cron job to run the data collector at an interval of your choice.

## Basic monitoring of Windows hosts

Pnacssh comes with a standard Windows template called _winbasic_. Follow steps below to monitor a Windows system (_winabc_ (ip 10.1.2.3) in examples) via pnacssh:

* Run pnacssh in config mode to create Nagios configuration files:
```
./pnacssh.pl --config --hostname winabc --template winbasic > <nagios configuration directory>
```
pnacssh in config mode will create host and services definitions for basic Windows monitoring on _winabc_.

* Run pnacssh in collector mode to create data collector which will be deployed on host _winabc_:
```
./pnacssh.pl --collector --hostname winabc --ip 10.1.2.3 --template winbasic
```
Pnacssh in collector mode will generate a data collector for host _winabc_ ready to use. Data collector content is in _staging/collector/winabc-winbasic_ directory.

* Transfer data collector directory securely to the host _winabc_. **NB!** This step is important as the data collector contains the private key. You need to make sure that that key arrives its host in a secure manner. Making an encrypted zip archive can be a solution.
* Copy data collector directory contents to a dedicated directory on winabc (_c:\pnacssh_ for example)
* Run the data collector directly to see if it performs checks and transfer results as expected
* Set up a scheduled task to run the data collector
