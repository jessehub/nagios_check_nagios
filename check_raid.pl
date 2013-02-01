#!/usr/bin/perl -w
#
# check_raid nagios plugin
#
# Add plugins for different RAID tools to function check
#
#
# Version 1.0-1
# Written by Fixar ()
#
package check_raid;
use Getopt::Long;
use File::Basename;
use Switch;
use strict;

sub new {
    my $type = shift;
    my $self = {
        _raidToolPath => '',
        _raidToolType => '',
        _helpFlag     => 0,
        _debugFile    => '',
        _versionFlag  => 0,
    };

    $self->{_raidInformation} = ();

    use constant VERSION                     => '1.0-2';
    use constant RAID_TOOL_TYPES   => ('megacli', 'megarc', 'zfs', 'hpacucli');
    use constant MONITOR_SERVICE   => 'RAID';
    use constant STATE_ONLINE      => 0;
    use constant STATE_DEGRADED    => 2;
    use constant STATE_FAILED      => 2;
    use constant STATE_UNKNOWN     => 3;

    $self->{_raidToolOptions} = {
        'megacli'  => '-LDPDInfo -aAll -NoLog',
        'megarc'   => '-ldInfo -a0 -Lall -NoLog',
        'hpacucli' => 'ctrl all show config',
        'zfs'      => 'status',
    };

    GetOptions(
      't=s' => \$self->{_raidToolType},
      'p=s' => \$self->{_raidToolPath},
      'h'   => \$self->{_helpFlag},
      'd=s' => \$self->{_debugFile},
        'v'   => \$self->{_versionFlag},
    );

    bless($self, $type);
    return $self;
}

# Return RAID tool options
sub getRaidToolOptions {
    my($self) = @_;
    return $self->{_raidToolOptions}->{$self->{_raidToolType}};
}


# Check using specified RAID tool
# Add plugins for different RAID tools here
sub check {
    my($self) = @_;
    my $raidToolOptions = $self->getRaidToolOptions;
    my @output;

    if ($self->{_debugFile}) {
        if (! -e $self->{_debugFile})  {
            print "Error: Debug file $self->{_debugFile} not found\n";
        } else {
            @output = `cat $self->{_debugFile}`;
        }
    } else {
        my $options = $self->getRaidToolOptions;
        chdir(dirname($self->{_raidToolPath}));
        @output = `$self->{_raidToolPath} $options`;

        if (!@output) {
            print "Error: Could not run $self->{_raidToolPath}, check permissions\n";
            exit &STATE_UNKNOWN;
        }
    }

    switch ($self->{_raidToolType}) {
        case 'megacli' {
            $self->checkMegacli(@output);
        }

        # megarc plugin
        case 'megarc' {
            $self->checkMegarc(@output);
        }
        # hpacucli plugin
        case 'hpacucli' {
            $self->checkHpacucli(@output);
        }

        # zfs plugin
        case 'zfs' {
            $self->checkZfs(@output);
        }
    }
}

# megacli plugin
sub checkMegacli {
    my($self) = @_;
    my @output = @_;
    #my @output = `$self->{_raidToolPath} -LDPDInfo -aAll -NoLog`;

    foreach (my $i = 0;$i < @output;$i++) {
        if (grep(/Virtual Disk: /, $output[$i])) {
            my %raidInfo;
            my @physicalDrives;

            if ($output[$i] =~ /Virtual Disk: (\w+).*/) {
                $raidInfo{'index'} = $1;   
            }
            if ($output[$i+2] =~ /RAID Level: Primary-(\w+).*/) {
                $raidInfo{'level'} = $1;   
            }
            if ($output[$i+4] =~ /State: (\w+).*/) {
                $raidInfo{'state'} = $1;   
            }
            switch ($raidInfo{'state'}) {
                case 'Optimal' {
                    $raidInfo{'state'} = 0;
                }
                case 'Degraded' {
                    $raidInfo{'state'} = 1;
                }
                case 'Partial Degraded' {
                    $raidInfo{'state'} = 1;
                }
                case 'Failed' {
                    $raidInfo{'state'} = 2;
                }
                case 'Offline' {
                    $raidInfo{'state'} = 2;
                }
                else {
                    $raidInfo{'state'} = 3;
                }
            }
            # Get physical drive info
            for (my $b = $i; $b < @output;$b++) {
                my %currentDrive;
                if ($output[$b] =~ /^PD: (\w+).*/) {
                    my $pd = $1;
                    if ($output[$b+1] =~ /^$/) {
                        #Output can be blank if there is an issue
                        $currentDrive{'slot'} = "PD: $pd";
                        $currentDrive{'state'} = 1;
                    } elsif ($output[$b+2] =~ /Slot Number: (\w+).*/) {
                        $currentDrive{'slot'} = $1;
                        if ($output[$b+13] =~ /Firmware state: (\w+).*/) {
                            $currentDrive{'state'} = ($1 eq 'Online') ? 0 : 1;   
                        }  
                    }
                    push(@physicalDrives, \%currentDrive);
                    # skip rest of info
                    $b = $b + 22;
                }  
            }
            push(@{$raidInfo{'physicalDrives'}}, @physicalDrives);
            push(@{$self->{_raidInformation}}, \%raidInfo);
        }
    }
}

# megarc plugin
sub checkMegarc {           
    my($self) = @_;
    my @output = @_;
    my @physicalDrives;
      my $position = 0;

    foreach (my $i = 0;$i < @output;$i++) {
        my %raidInfo;
        if ($output[$i] =~ /.*Logical Drive \w+ :.*$/) {
            $position = $i;
            last;
        }
        if ($output[$i] =~ /Logical Drive : (\w+).*Status: (\w+)/) {
            $raidInfo{'index'} = $1;   
            $raidInfo{'state'} = $2;

            if ($output[$i + 2] =~ /.* RaidLevel: (\w+)/) {
                $raidInfo{'level'} = $1;
            }

            switch ($raidInfo{'state'}) {
                case 'OPTIMAL' {
                    $raidInfo{'state'} = 0;
                }
                case 'DEGRADED' {
                    $raidInfo{'state'} = 1;
                }
                case 'FAILED' {
                    $raidInfo{'state'} = 2;
                }
                else {
                    $raidInfo{'state'} = 3;
                }
            }
            push(@{$self->{_raidInformation}}, \%raidInfo);
        }
  }           
    my $count = 0;
  for (my $b = $position - 1; $b < @output;$b++) {
        if ($output[$b] =~ /.*Logical Drive (\w+) :.*/) {
            for(my $c = $b + 3;$c < @output;$c++) {
                my %currentDrive;
                if ($output[$c] =~ /.*\d+\s+(\d+)\s+\w+\s+\w+\s+(\w+).*/) {
                    $currentDrive{'slot'} = $1;
                    $currentDrive{'state'} = ($2 eq 'ONLINE') ? 0 : 1;
                    push(@physicalDrives, \%currentDrive);
                }
            }
            push(@{$self->{_raidInformation}[$count]->{physicalDrives}}, @physicalDrives);
            $count++;
        }
    }
}

# hpacucli plugin
sub checkHpacucli {
    my($self) = @_;   
    my @output = @_;

    foreach (my $i = 0;$i < @output;$i++) {
        my %raidInfo;
        if($output[$i] =~ /logicaldrive (\w+) .* RAID (.*), (\w+)/) {
            $raidInfo{'level'} = $2;
            $raidInfo{'index'} = $1;
            switch ($3) {
                case 'OK' {
                    $raidInfo{'state'} = 0;
                }
                case 'FAILED' {
                    $raidInfo{'state'} = 2;
                }
                else {
                    $raidInfo{'state'} = 3;
                }
            }

            # Get physical drive info
            my @physicalDrives;
            for (my $b = $i + 1; $b < @output;$b++) {
                my %currentDrive;
                if ($output[$b] =~ /\s*physicaldrive .* \(\w+.*bay (\w+), \w+, \w+ \w+, (\w+)\)/) {
                    $currentDrive{'slot'} = $1;
                    $currentDrive{'state'} = ($2 eq 'OK') ? 0 : 1;
                    push(@physicalDrives, \%currentDrive);
                }  
                if ($output[$b] =~ / *logicaldrive*/) {
                    last;
                }   
            }
            push(@{$raidInfo{'physicalDrives'}}, @physicalDrives);
            push(@{$self->{_raidInformation}}, \%raidInfo);
        }
    }
}

# zfs plugins
sub checkZfs {
    my($self) = @_;
    my $count = 0;
    my @output = @_;
    #my @output = `$self->{_raidToolPath} status`;

    foreach (my $i = 0;$i < @output;$i++) {
        my %raidInfo;
        if ($output[$i] =~ /^\s*raidz(\w)\s*(\w+).*$/) {
            $raidInfo{'level'} = $1;               
            $raidInfo{'index'} = $count;           
            switch ($2) {
                case 'ONLINE' {
                    $raidInfo{'state'} = 0;
                }
                case 'DEGRADED' {
                    $raidInfo{'state'} = 2;
                }
                else {
                    $raidInfo{'state'} = 3;
                }
            }
           
            # Get physical drive info
            my @physicalDrives;
            for (my $b = $i+1; $b < @output;$b++) {
                my %currentDrive;
                if ($output[$b] =~ /^\s*raidz.*$|^\s*spares.*$/) {
                    last;
                }
                if ($output[$b] =~ /^\s*(\w+)\s*(\w+).*$/) {
                    $currentDrive{'slot'} = $1;
                    $currentDrive{'state'} = ($2 eq 'ONLINE') ? 0 : 1;
                }  
                push(@physicalDrives, \%currentDrive);
                   
            }
            push(@{$raidInfo{'physicalDrives'}}, @physicalDrives);
            push(@{$self->{_raidInformation}}, \%raidInfo);
            $count++;
        }
    }
}

# Parse arguments
sub parseOptions {
    my($self) = @_;

    # Check for help flag
    if ($self->{_helpFlag}) {
        $self->usage;
    }
   
    # Check for version flag
    if ($self->{_versionFlag}) {
        $self->version;
    }

    # Make sure variables are set
    if (!$self->{_raidToolType} || !$self->{_raidToolPath}) {
        print "Error: Specify a RAID tool type and path\n";
        exit &STATE_UNKNOWN;
    }

    # Check for valid RAID tool
    my $validRaidTool = 0;
    foreach (&RAID_TOOL_TYPES) {
        if ($self->{_raidToolType} eq $_) {
            $validRaidTool = 1;
        }
    }
   
    if (!$validRaidTool) {
        print "Error: Invalid RAID tool type specified\n";
        exit &STATE_UNKNOWN;
    }

    # Check if RAID tool exists
    if (! -e $self->{_raidToolPath}) {
        print "Error: RAID tool '$self->{_raidToolPath}' does not exists\n";
        exit &STATE_UNKNOWN;
    }
}

# Prints usage
sub usage {
    print "Usage: check_raid -t [RAID tool type] -p [RAID tool path]\n";
    exit &STATE_UNKNOWN;
}

# Prints version
sub version {
    print &VERSION . "\n";
    exit &STATE_UNKNOWN;
}

# Print result string
sub formatOutput {
    my($self) = @_;
    my $resultString = '';

    foreach (@{$self->{_raidInformation}}) {
        my $state;
        switch ($_->{'state'}) {
            case 0 {
                $state = 'Online';
            }
            case 1 {
                $state = 'Degraded';
            }
            case 2 {
                $state = 'Failed';
            }
            case 3 {
                $state = 'Unknown';
            }
            else {
                $state = 'Unknown';
            }
        }
        $resultString .= "Volume: $_->{'index'}, State: $state, Level: $_->{'level'} ; ";
    }
    return $resultString;
}

# Find the exit code
sub getExitCode {
    my($self) = @_;
    my $state = -1;
    foreach (@{$self->{_raidInformation}}) {
        if ($_->{'state'} == 0) {
            $state = &STATE_ONLINE;
        }
        if ($_->{'state'} == 1) {
            return &STATE_DEGRADED;
        }
        if ($_->{'state'} == 2) {
            return &STATE_FAILED;
        }
        if ($_->{'state'} == 3) {
            return &STATE_UNKNOWN;
        }
    }
    return $state;
}

# Gets physical drive data for alerts
sub formatAlerts {
    my($self) = @_;
    my $resultString = '[Issues on: ';

    foreach (@{$self->{_raidInformation}}) {
        my @failedDrives;
        my $currentIndex = $_->{'index'};
        foreach (@{$_->{'physicalDrives'}}) {
            if ($_->{'state'} == 1) {
                push(@failedDrives, $_->{'slot'});
            }
        }
        if (@failedDrives) {
            foreach (@failedDrives) {
                $resultString .= "Volume $currentIndex/Slot $_;";
            }
        }
    }

    $resultString .= ']';
    return $resultString;
}


# Output and return with exit code
#
# raidInformation has form:
# - Logical Volume (Number)
#   - index
#   - State
#   - Level
#   - physical drives
#
sub output {
    my($self) = @_;
    switch ($self->getExitCode) {
        case 0 {
            print &MONITOR_SERVICE . " OK - " . $self->formatOutput;
        }
        case 2 {
            print &MONITOR_SERVICE . " CRITICAL - " . $self->formatOutput . ' ' . $self->formatAlerts;
        }
        case 3 {
            print &MONITOR_SERVICE . " UNKNOWN - " . $self->formatOutput . $self->formatAlerts;
        }
        else {
            print &MONITOR_SERVICE . " UNKNOWN";
        }
    }
    print "\n";
    exit $self->getExitCode();
}

#
# Main run
#
my $checkRaid = check_raid->new('check_raid');
$checkRaid->parseOptions;
$checkRaid->check;
$checkRaid->output;
