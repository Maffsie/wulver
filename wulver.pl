#!/usr/bin/env perl
#wulver - Runs specified checks at set intervals, on preconfigured hosts

=begin LICENSE
Copyright (c) 2012, Matthew Connelly
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
- Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
- Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
- Neither the name of the software nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
=cut

#TODO
#In order of importance
# - Implement check result handling.
# - Implement alerts, alert config and alert handlers
# - Implement "helper" functions, which make it easy to simply check if a given port is open and so on
# - Write more checks

#Standard perl stuff
use strict;
use warnings;
#Libraries and stuff need for the base system to operate
use threads;
use threads::shared;
use Proc::Daemon;
use Date::Format;
use File::Spec;
#Libraries needed for specific checks
use Net::Ping;

#Configuration
#Hosts. These can be either DNS names or IP addresses. This is in the format: "friendlyname" => "server address",
our %hosts = (
);

#Check configuration
#Ping check configuration. This is in the format: "friendlyname",
our @check_Ping_hosts = (
);
#SSH Check configuration. This is in the format: "friendlyname" => "SSH port",
our %check_SSH_hosts = (
);

#Check running configuration.
#List each check you wish to run, along with the frequency. Frequency config has yet to be decided.
#0 = Never, 1 = Every Minute
our %check_Config = (
	"SSH"	=> 0,
	"Ping"	=> 0,
);

#Alert config
#Enabled alert handlers
our %alerts = (
	"SMS"			=> 0, #SMS notifications
	"Email"			=> 0, #Email notifications
	"Jabber"		=> 0, #XMPP/Jabber IM notifications
	"Twitter"		=> 0, #Tweet notifications
	"RPi_GPIO_LED"	=> 0, #Display check states using LEDs connected to the GPIO pins on a raspberry pi
	"RPi_GPIO_DISP"	=> 0, #Display check states using a text display connected to the GPIO pins on a raspberry pi
);
#Alert contacts. Currently, this will just send alerts to all contacts.
#I might in the future add support for sending notifications to specific contacts under certain conditions.
our @alertContacts_SMS = (
);
our @alertContacts_Email = (
);
our @alertContacts_Jabber = (
);
our @alertContacts_Twitter = (
);

#Checks
#Ping check. Check if the hosts are responding to ping.
sub check_Ping {
	my $checkName = "Ping";
	logger("Running ping check");
	foreach(@check_Ping_hosts) {
		my $pinger = Net::Ping->new();
		logger("Checking ping for $_");
		if($pinger->ping($hosts{$_})) {
			logger("Check succeeded.");
		} else {
			logger("Check failed.");
		}
	}
}
#SSH Check. Check if the hosts have SSH running.
sub check_SSH {
	my $checkName = "SSH";
	my $host;
	my $port;
	logger("Running SSH check");
	while(($host, $port) = each(%check_SSH_hosts)) {
		logger("Checking SSH for $host");
	}
}


#Alert handlers
#SMS
sub alertHandler_SMS {
	#SMS alert handler.
	#This uses Tropo. Tropo developer accounts are free, unlimited and enable you to send SMS messages.
	#This by no means restricts you to using Tropo as your SMS gateway - feel free to replace the tropo API code with the equivalents for your preferred SMS gateway
	my($alertTemplate,$alertMessage);
	$alertTemplate = "PERLMON ALERT @ ".Date::Format::time2str('%e %B %T', time).": ";
	#Code to form the alert message should eventually go here
	$alertMessage = "No alert message set.";
	my $tropoAPIToken = "";
	my $tropoURL = "https://api.tropo.com/1.0/sessions?action=create&token={$tropoAPIToken}&alertMsg={$alertTemplate}{$alertMessage}";
	foreach(@alertContacts_SMS) {
		my $reqURI = "{$tropoURL}&myNumber=$_";
		my $result = `curl -s "$reqURI"`;
		chomp $result;
	}
}

#Main program -- Don't change anything past this line unless you know what you're doing!
#Daemon stuff
our $ME = "wulver";
our $VERSION = "0.1";
#TODO Implement PID file handling, prevent multiple instances from running and handle instances where the pidfile exists but the process it references doesn't.
#PID and logfile locations. These should exist and be readable and writeable by the user that wulver is running as.
our $PIDFILE = "/var/run/$ME.pid";
our $LOG_FILE = "/var/log/$ME.log";
startDaemon();

#Logging
#Get hostname
our $HOSTNAME = `hostname`;
chomp $HOSTNAME;
#Redirect standard output and error output to the log file
open(STDOUT, ">>$LOG_FILE");
open(STDERR, ">>$LOG_FILE");
#Make the logfile handle "hot" so changes are written immediately, to prevent issues with perl I/O buffering
select((select(STDOUT), $|=1)[0]);
logger("Starting $ME...");

#Signal handling
my $running = 1;
#TODO Write proper event handlers for signals
$SIG{HUP} = sub { logger("Caught SIGHUP: Exiting.."); $running = 0; };
$SIG{INT} = sub { logger("Caught SIGINT: Exiting.."); $running = 0; };
$SIG{QUIT} = sub { logger("Caught SIGQUIT: Exiting.."); $running = 0; };
$SIG{TERM} = sub { logger("Caught SIGTERM: Exiting.."); $running = 0; };



#Main Loop
while($running) {
	#I don't see a need to run checks more than once a second, it'd only add unnecessary complexity.
	run_checks();
	sleep 1;
}

#Loop stopped, program's ending.
logger("Stopping $ME...");

#Functions
sub startDaemon {
	eval { Proc::Daemon::Init; };
	if($@) {
		dienice("Unable to start $ME daemon: $@");
	}
	#dienice("Already running!") if hold_pid_file($PIDFILE);
}

sub run_checks {
	my($secs,$mins,$hours,$day,$month,$year,$wday,$yday,$dst);
	($secs,$mins,$hours,$day,$month,$year,$wday,$yday,$dst) = localtime(time);
	my($check_Name, $check_Duration);
	while(($check_Name, $check_Duration) = each(%check_Config)) {
		if($check_Duration == 1 && $secs == 0) {
			my($thrChk);
			$thrChk = threads->create("check_$check_Name");
			$thrChk->detach();
		}
	}
}

sub run_alert_handlers {
	my($alertHandlerName,$enabled);
	while(($alertHandlerName,$enabled) = each(%alerts)) {
		if($enabled == 1) {
			my $thrAlertHandler;
			$thrAlertHandler = threads->create("alertHandler_$alertHandlerName");
			$thrAlertHandler->detach();
		}
	}
}

sub logger {
	my($logmsg) = @_;
	print(Date::Format::time2str('%e %B %T', time)." ".$HOSTNAME." $ME\[$$]: ".$logmsg."\n");
}

sub dienice($) {
	my ($package, $filename, $line) = caller;
	logger("$_[0] at line $line in $filename");
	die $_[0];
}
