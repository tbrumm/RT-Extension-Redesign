package RT::Extension::Redesign;

our $VERSION = '0.08';

use strict;
use warnings;

sub collect_stats {
    my $dbh = $RT::Handle->dbh;
    my %s;

    # --- Global (Scrips / Templates / Conditions / Actions) ---
    ($s{global}{st}) = $dbh->selectrow_array("SELECT COUNT(*) FROM Scrips");
    ($s{global}{sd}) = $dbh->selectrow_array("SELECT COUNT(*) FROM Scrips WHERE Disabled = 1");
    ($s{global}{sg}) = $dbh->selectrow_array(
        "SELECT COUNT(DISTINCT Scrip) FROM ObjectScrips WHERE ObjectId = 0"
    );
    $s{global}{sq} = $s{global}{st} - $s{global}{sg};

    ($s{global}{tt}) = $dbh->selectrow_array("SELECT COUNT(*) FROM Templates");
    ($s{global}{tg}) = $dbh->selectrow_array("SELECT COUNT(*) FROM Templates WHERE ObjectID = 0");
    $s{global}{tq} = $s{global}{tt} - $s{global}{tg};

    ($s{global}{ct}) = $dbh->selectrow_array("SELECT COUNT(*) FROM ScripConditions");
    ($s{global}{at}) = $dbh->selectrow_array("SELECT COUNT(*) FROM ScripActions");

    # --- Tools ---
    ($s{tools}{ds}) = $dbh->selectrow_array(
        "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 1)
         FROM information_schema.tables WHERE table_schema = DATABASE()"
    );
    $s{tools}{ds} //= 0;
    ($s{tools}{cr}) = $dbh->selectrow_array("SELECT COUNT(*) FROM CustomRoles");
    ($s{tools}{sp}) = $dbh->selectrow_array(
        "SELECT COUNT(*) FROM Attributes WHERE Name = 'ScheduledProcess'"
    );
    ($s{tools}{se}) = $dbh->selectrow_array(
        "SELECT COUNT(*) FROM Transactions WHERE Type = 'SystemError'"
    );

    # --- Articles ---
    my $cl = $dbh->selectall_arrayref(
        "SELECT Disabled, COUNT(*) FROM Classes GROUP BY Disabled"
    );
    my %cld; $cld{$_->[0]} = $_->[1] for @$cl;
    $s{articles}{ca} = $cld{0} // 0;
    $s{articles}{ct} = ($cld{0} // 0) + ($cld{1} // 0);

    my $ar = $dbh->selectall_arrayref(
        "SELECT Disabled, COUNT(*) FROM Articles GROUP BY Disabled"
    );
    my %ard; $ard{$_->[0]} = $_->[1] for @$ar;
    $s{articles}{aa} = $ard{0} // 0;
    $s{articles}{at} = ($ard{0} // 0) + ($ard{1} // 0);

    # --- Assets ---
    my $rows = $dbh->selectall_arrayref(
        "SELECT Status, COUNT(*) FROM Assets GROUP BY Status"
    );
    my %by_status; $by_status{$_->[0]} = $_->[1] for @$rows;
    $s{assets}{aa} = $by_status{allocated} // 0;
    $s{assets}{ai} = $by_status{'in-use'}  // 0;
    $s{assets}{ao} = 0;
    for my $st (keys %by_status) {
        next if $st eq 'allocated' || $st eq 'in-use';
        $s{assets}{ao} += $by_status{$st};
    }
    $s{assets}{at} = $s{assets}{aa} + $s{assets}{ai} + $s{assets}{ao};

    my $cat = $dbh->selectall_arrayref(
        "SELECT Disabled, COUNT(*) FROM Catalogs GROUP BY Disabled"
    );
    my %catd; $catd{$_->[0]} = $_->[1] for @$cat;
    $s{assets}{ca} = $catd{0} // 0;
    $s{assets}{ct} = ($catd{0} // 0) + ($catd{1} // 0);

    # --- Custom Fields ---
    my $cfrows = $dbh->selectall_arrayref(
        "SELECT LookupType, COUNT(*) FROM CustomFields WHERE Disabled = 0 GROUP BY LookupType"
    );
    my %by_type; $by_type{$_->[0]} = $_->[1] for @$cfrows;
    $s{cf}{ti} = $by_type{'RT::Queue-RT::Ticket'}                 // 0;
    $s{cf}{as} = $by_type{'RT::Catalog-RT::Asset'}                // 0;
    $s{cf}{us} = $by_type{'RT::User'}                             // 0;
    $s{cf}{ar} = $by_type{'RT::Class-RT::Article'}                // 0;
    $s{cf}{tr} = $by_type{'RT::Queue-RT::Ticket-RT::Transaction'} // 0;
    $s{cf}{to} = 0;
    $s{cf}{to} += $_ for values %by_type;

    # --- Login page ---
    ($s{login}{priv}) = $dbh->selectrow_array(
        "SELECT COUNT(gm.MemberId)
         FROM GroupMembers gm
         JOIN Groups g ON gm.GroupId = g.id
         JOIN Principals p ON gm.MemberId = p.id
         WHERE g.Domain = 'SystemInternal' AND g.Name = 'Privileged'
           AND p.PrincipalType = 'User' AND p.Disabled = 0"
    );
    ($s{login}{unpriv}) = $dbh->selectrow_array(
        "SELECT COUNT(gm.MemberId)
         FROM GroupMembers gm
         JOIN Groups g ON gm.GroupId = g.id
         JOIN Principals p ON gm.MemberId = p.id
         WHERE g.Domain = 'SystemInternal' AND g.Name = 'Unprivileged'
           AND p.PrincipalType = 'User' AND p.Disabled = 0"
    );
    ($s{login}{groups})   = $dbh->selectrow_array("SELECT COUNT(*) FROM Groups WHERE Domain = 'UserDefined'");
    ($s{login}{queues})   = $dbh->selectrow_array("SELECT COUNT(*) FROM Queues");
    ($s{login}{tickets})  = $dbh->selectrow_array("SELECT COUNT(*) FROM Tickets");
    ($s{login}{txns})     = $dbh->selectrow_array("SELECT COUNT(*) FROM Transactions");
    ($s{login}{assets})   = $dbh->selectrow_array("SELECT COUNT(*) FROM Assets");
    ($s{login}{articles}) = $dbh->selectrow_array("SELECT COUNT(*) FROM Articles");

    $s{refreshed_at} = time();
    return \%s;
}

1;

=head1 NAME

RT::Extension::Redesign - Modern UI redesign for Request Tracker 6

=head1 DESCRIPTION

A complete UI redesign for RT6. Provides a modern look and feel while
preserving the standard top navigation structure.

=head1 INSTALLATION

    perl Makefile.PL
    make
    sudo make install

Then add to F</opt/rt6/etc/RT_SiteConfig.pm>:

    Plugin('RT::Extension::Redesign');

Clear Mason cache and restart Apache:

    sudo rm -rf /opt/rt6/var/mason_data/obj/*
    sudo service apache2 restart

=head1 AUTHOR

Torsten Brumm

=head1 LICENSE

GPL version 2

=cut
