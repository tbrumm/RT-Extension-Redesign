package RT::Extension::Redesign;

our $VERSION = '0.10';

use strict;
use warnings;

# Allow language-* CSS classes through RT's HTML scrubber so that
# highlight.js code blocks are not stripped on ticket display.
require RT::Interface::Web::Scrubber;
{
    no warnings 'once';
    package RT::Interface::Web::Scrubber;
    our %ALLOWED_ATTRIBUTES;
    $ALLOWED_ATTRIBUTES{class} = qr/(text-|fw-|fst-|fs-|align-|\btable\b|language-)/;
}

sub collect_stats {
    my $dbh = $RT::Handle->dbh;
    my %s;

    # --- Global (Scrips / Templates / Conditions / Actions) ---
    eval {
        ($s{global}{st}) = $dbh->selectrow_array("SELECT COUNT(*) FROM Scrips");
        ($s{global}{sd}) = $dbh->selectrow_array("SELECT COUNT(*) FROM Scrips WHERE Disabled = 1");
        ($s{global}{sg}) = $dbh->selectrow_array(
            "SELECT COUNT(DISTINCT Scrip) FROM ObjectScrips WHERE ObjectId = 0"
        );
        $s{global}{sq} = ($s{global}{st} // 0) - ($s{global}{sg} // 0);

        ($s{global}{tt}) = $dbh->selectrow_array("SELECT COUNT(*) FROM Templates");
        ($s{global}{tg}) = $dbh->selectrow_array("SELECT COUNT(*) FROM Templates WHERE ObjectID = 0");
        $s{global}{tq} = ($s{global}{tt} // 0) - ($s{global}{tg} // 0);

        ($s{global}{ct}) = $dbh->selectrow_array("SELECT COUNT(*) FROM ScripConditions");
        ($s{global}{at}) = $dbh->selectrow_array("SELECT COUNT(*) FROM ScripActions");
    };
    RT::Logger->error("Redesign collect_stats [global]: $@") if $@;
    $s{global}{$_} //= 0 for qw(st sd sg sq tt tg tq ct at);

    # --- Tools ---
    eval {
        ($s{tools}{ds}) = $dbh->selectrow_array(
            "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 1)
             FROM information_schema.tables WHERE table_schema = DATABASE()"
        );
        ($s{tools}{cr}) = $dbh->selectrow_array("SELECT COUNT(*) FROM CustomRoles");
        ($s{tools}{sp}) = $dbh->selectrow_array(
            "SELECT COUNT(*) FROM Attributes WHERE Name = 'ScheduledProcess'"
        );
        ($s{tools}{se}) = $dbh->selectrow_array(
            "SELECT COUNT(*) FROM Transactions WHERE Type = 'SystemError'"
        );
    };
    RT::Logger->error("Redesign collect_stats [tools]: $@") if $@;
    $s{tools}{$_} //= 0 for qw(ds cr sp se);

    # --- Articles ---
    eval {
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
    };
    RT::Logger->error("Redesign collect_stats [articles]: $@") if $@;
    $s{articles}{$_} //= 0 for qw(ca ct aa at);

    # --- Assets ---
    eval {
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
    };
    RT::Logger->error("Redesign collect_stats [assets]: $@") if $@;
    $s{assets}{$_} //= 0 for qw(aa ai ao at ca ct);

    # --- Custom Fields ---
    eval {
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
    };
    RT::Logger->error("Redesign collect_stats [cf]: $@") if $@;
    $s{cf}{$_} //= 0 for qw(ti as us ar tr to);

    # --- Login page ---
    # `Groups` prefix required for MySQL 8 (GROUPS is a reserved keyword)
    eval {
        ($s{login}{priv}) = $dbh->selectrow_array(
            "SELECT COUNT(gm.MemberId)
             FROM GroupMembers gm
             JOIN `Groups` g ON gm.GroupId = g.id
             JOIN Principals p ON gm.MemberId = p.id
             WHERE g.Domain = 'SystemInternal' AND g.Name = 'Privileged'
               AND p.PrincipalType = 'User' AND p.Disabled = 0"
        );
        ($s{login}{unpriv}) = $dbh->selectrow_array(
            "SELECT COUNT(gm.MemberId)
             FROM GroupMembers gm
             JOIN `Groups` g ON gm.GroupId = g.id
             JOIN Principals p ON gm.MemberId = p.id
             WHERE g.Domain = 'SystemInternal' AND g.Name = 'Unprivileged'
               AND p.PrincipalType = 'User' AND p.Disabled = 0"
        );
        ($s{login}{groups})   = $dbh->selectrow_array(
            "SELECT COUNT(*) FROM `Groups` WHERE Domain = 'UserDefined'"
        );
        ($s{login}{queues})   = $dbh->selectrow_array("SELECT COUNT(*) FROM Queues");
        ($s{login}{tickets})  = $dbh->selectrow_array("SELECT COUNT(*) FROM Tickets");
        ($s{login}{txns})     = $dbh->selectrow_array("SELECT COUNT(*) FROM Transactions");
        ($s{login}{assets})   = $dbh->selectrow_array("SELECT COUNT(*) FROM Assets");
        ($s{login}{articles}) = $dbh->selectrow_array("SELECT COUNT(*) FROM Articles");
    };
    RT::Logger->error("Redesign collect_stats [login]: $@") if $@;
    $s{login}{$_} //= 0 for qw(priv unpriv groups queues tickets txns assets articles);

    # --- Admin overview (for Admin/index.html) ---
    # `Groups` prefix required for MySQL 8 (GROUPS is a reserved keyword)
    eval {
        my $q_rows = $dbh->selectall_arrayref(
            "SELECT Disabled, COUNT(*) FROM Queues WHERE id > 0 GROUP BY Disabled"
        );
        my %qd; $qd{$_->[0]} = $_->[1] for @$q_rows;
        $s{admin}{qa} = $qd{0} // 0;
        $s{admin}{qt} = ($qd{0} // 0) + ($qd{1} // 0);

        my $cf_rows = $dbh->selectall_arrayref(
            "SELECT Disabled, COUNT(*) FROM CustomFields GROUP BY Disabled"
        );
        my %cfd; $cfd{$_->[0]} = $_->[1] for @$cf_rows;
        $s{admin}{ca} = $cfd{0} // 0;
        $s{admin}{ct} = ($cfd{0} // 0) + ($cfd{1} // 0);

        ($s{admin}{g}) = $dbh->selectrow_array(
            "SELECT COUNT(*) FROM `Groups` WHERE Domain = 'UserDefined'"
        );

        my $u_rows = $dbh->selectall_arrayref(
            "SELECT gm.GroupId, COUNT(DISTINCT u.id)
             FROM Users u
             JOIN GroupMembers gm ON gm.MemberId = u.id
             JOIN Principals p ON p.id = u.id
             WHERE gm.GroupId IN (4, 5) AND p.Disabled = 0 AND u.id > 2
             GROUP BY gm.GroupId"
        );
        my %ug; $ug{$_->[0]} = $_->[1] for @$u_rows;
        $s{admin}{up} = $ug{4} // 0;
        $s{admin}{uu} = $ug{5} // 0;

        ($s{admin}{ud}) = $dbh->selectrow_array(
            "SELECT COUNT(*) FROM Principals
             WHERE Disabled = 1 AND PrincipalType = 'User' AND id > 2"
        );

        my $t_rows = $dbh->selectall_arrayref(
            "SELECT Status, COUNT(*) FROM Tickets WHERE id > 0 GROUP BY Status"
        );
        my %by_status; $by_status{$_->[0]} = $_->[1] for @$t_rows;
        my @done = qw(resolved rejected done ClosedByHousekeeping on_hold cancelled);
        $s{admin}{tn} = $by_status{new}     // 0;
        $s{admin}{td} = $by_status{deleted} // 0;
        $s{admin}{tr} = 0;
        $s{admin}{tr} += ($by_status{$_} // 0) for @done;
        $s{admin}{ta} = 0;
        for my $status (keys %by_status) {
            next if $status eq 'new' || $status eq 'deleted'
                 || grep { $_ eq $status } @done;
            $s{admin}{ta} += $by_status{$status};
        }
    };
    RT::Logger->error("Redesign collect_stats [admin]: $@") if $@;
    $s{admin}{$_} //= 0 for qw(qa qt ca ct g up uu ud tn ta tr td);

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
