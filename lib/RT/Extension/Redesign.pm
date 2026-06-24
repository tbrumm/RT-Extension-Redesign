package RT::Extension::Redesign;

our $VERSION = '0.24';

use 5.010001;
use strict;
use warnings;
use POSIX ();
use JSON::PP ();

# Allow language-* CSS classes through RT's HTML scrubber so that
# highlight.js code blocks are not stripped on ticket display.
require RT::Interface::Web::Scrubber;
{
    no warnings 'once';
    package RT::Interface::Web::Scrubber;
    our %ALLOWED_ATTRIBUTES;
    $ALLOWED_ATTRIBUTES{class} = qr/(text-|fw-|fst-|fs-|align-|\btable\b|language-)/;
}

# LoginShowPromo: when no maintenance banner is active, optionally show the
# "Why Request Tracker?" promo grid on the login page. The Meta Default below is
# the single source of truth — active from Plugin('RT::Extension::Redesign')
# alone; an admin overrides it with Set($LoginShowPromo, 1) in RT_SiteConfig.pm.
# Registered Immutable so RT renders it read-only in the admin "System
# Configuration" UI (refuses a database override; the file override still works).
# The eval guard keeps the module loadable standalone (unit tests) where RT is
# not initialised.
if ( eval { RT->can('Config') && RT->Config && RT->Config->can('RegisterPluginConfig') } ) {
    RT->Config->RegisterPluginConfig(
        Plugin  => 'Redesign',
        Content => [ { Name => 'LoginShowPromo' } ],
        Meta    => {
            LoginShowPromo => {
                Type            => 'SCALAR',
                Default         => 0,
                Immutable       => 1,
                Widget          => '/Widgets/Form/Boolean',
                WidgetArguments => {
                    Description => 'Show the "Why Request Tracker?" promo grid on the login page when no maintenance banner is active',  # loc
                },
            },
        },
    );
}

# Front-end assets ship as external files under static/ and are registered here,
# never as inline <script>/<style> in Mason: RT6's <body hx-boost="true"> swaps
# the body on every navigation, so inline scripts and DOMContentLoaded listeners
# do not reliably re-run. The eval guard keeps the module loadable standalone
# (unit tests) where RT is not initialised.
if ( eval { RT->can('AddJavaScript') } ) {
    RT->AddJavaScript('redesign/redesign-global.js');
}

=head2 banner_is_active($data, $today)

Decide whether the maintenance/login banner configured on
F</Admin/Global/LoginBanner.html> should be shown. C<$data> is the
C<MaintenanceBannerData> attribute content (a hashref); C<$today> is a
C<YYYY-MM-DD> date string. Returns true when the banner is enabled and either
has no expiry or its expiry date has not yet passed (the expiry day itself is
inclusive). A missing C<enabled> key defaults to on, matching the admin page.

=cut

=head2 banner_defaults

Default headline and German/English content for the login maintenance banner,
used both by the F</Admin/Global/LoginBanner.html> editor (as the pre-filled
values) and by the login-page display callback when no content has been saved
yet. Returns a hashref with C<headline>, C<content_de> and C<content_en>.

=cut

sub banner_defaults {
    return {
        headline   => 'Willkommen &nbsp;&bull;&nbsp; Welcome',
        content_de => '<p>Willkommen bei Request Tracker.</p>
<p>Dieser Hinweis ist ein Platzhalter. Administratoren k&ouml;nnen ihn unter <strong>Admin &rarr; Global &rarr; Login Banner</strong> bearbeiten, als Info- oder Warnhinweis gestalten oder ganz ausblenden.</p>',
        content_en => '<p>Welcome to Request Tracker.</p>
<p>This notice is a placeholder. Administrators can edit it under <strong>Admin &rarr; Global &rarr; Login Banner</strong>, style it as an info or warning message, or hide it entirely.</p>',
    };
}

=head2 format_refreshed_at($epoch, CurrentUser => $cu)

Format the C<refreshed_at> epoch of the C<AdminDashboardStats> attribute for
display as C<dd.mm.yyyy HH:MM>. The stored value is an absolute Unix epoch; the
timezone is applied only here. With a C<CurrentUser> the value is rendered in
that user's own timezone preference (the admin dashboards); without one it is
rendered in the RT server timezone (C<$Timezone> config — normally UTC), used by
the login page where there is no user context. Returns the empty string for a
missing/zero epoch, so callers render the "last update" note only when stats
have actually been collected. Shared by the login page and the admin
F</Elements/StatsRefreshedNote> so the format stays consistent.

=cut

sub format_refreshed_at {
    my ($epoch, %args) = @_;
    return '' unless $epoch;

    my $cu      = $args{CurrentUser};
    my $context = $cu ? 'user' : 'server';

    my $date = RT::Date->new( $cu || RT->SystemUser );
    $date->Set( Format => 'unix', Value => $epoch );

    my @lt = $date->Localtime($context);   # sec,min,hour,mday,mon(0-11),year(4)
    return sprintf( '%02d.%02d.%04d %02d:%02d',
                    $lt[3], $lt[4] + 1, $lt[5], $lt[2], $lt[1] );
}

=head2 encode_js_json($data)

JSON-encode C<$data> for safe interpolation into an inline HTML C<< <script> >>
block (emit with C<< <% ... |n %> >>). Two guards: C<ascii(1)> keeps the output
pure ASCII so no utf8-flagged C<loc()> bytes reach the Mason buffer, and every
C</> is escaped to C<\/> so a value containing C<< </script> >> cannot close the
script element and break out — the same protection RT's own C<JSON()> helper
applies (F<lib/RT/Interface/Web.pm>). C<$data> may be a scalar or a reference.

=cut

sub encode_js_json {
    my $data = shift;
    my $json = JSON::PP->new->ascii(1)->allow_nonref->encode($data);
    $json =~ s{/}{\\/}g;
    return $json;
}

=head2 strip_outer_paragraph($html)

Remove a single enclosing C<< <p>…</p> >> wrapper from C<$html>. CKEditor wraps
even one-line content in a paragraph; the login banner renders the headline
inside an C<< <h2> >>, where a nested C<< <p> >> would look wrong. Only unwraps
when the whole value is exactly one paragraph (bails on sibling/nested
paragraphs so multi-paragraph HTML is never corrupted). Returns the empty string
for undef.

=cut

sub strip_outer_paragraph {
    my $html = shift // '';
    if ( $html =~ m{\A\s*<p\b[^>]*>(.*)</p>\s*\z}s ) {
        my $inner = $1;
        return $inner unless $inner =~ m{</?p\b}i;
    }
    return $html;
}

sub banner_is_active {
    my ($data, $today) = @_;
    return 0 unless ref $data eq 'HASH';

    my $enabled = exists $data->{enabled} ? $data->{enabled} : 1;
    return 0 unless $enabled;

    my $expiry = $data->{expiry};
    return 1 unless defined $expiry && length $expiry;

    return $expiry ge $today ? 1 : 0;
}

sub collect_stats {
    my $dbh = $RT::Handle->dbh;
    my %s;

    # `Groups` is a reserved word in MySQL 8; quote_identifier emits the right
    # identifier quoting for whichever DB driver is active (backticks on MySQL,
    # double quotes on PostgreSQL/Oracle/SQLite).
    my $groups = $dbh->quote_identifier('Groups');

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
    # Groups table is quoted via $groups (see quote_identifier above) because
    # GROUPS is a reserved word in MySQL 8.
    eval {
        ($s{login}{priv}) = $dbh->selectrow_array(
            "SELECT COUNT(gm.MemberId)
             FROM GroupMembers gm
             JOIN $groups g ON gm.GroupId = g.id
             JOIN Principals p ON gm.MemberId = p.id
             WHERE g.Domain = 'SystemInternal' AND g.Name = 'Privileged'
               AND p.PrincipalType = 'User' AND p.Disabled = 0"
        );
        ($s{login}{unpriv}) = $dbh->selectrow_array(
            "SELECT COUNT(gm.MemberId)
             FROM GroupMembers gm
             JOIN $groups g ON gm.GroupId = g.id
             JOIN Principals p ON gm.MemberId = p.id
             WHERE g.Domain = 'SystemInternal' AND g.Name = 'Unprivileged'
               AND p.PrincipalType = 'User' AND p.Disabled = 0"
        );
        ($s{login}{groups})   = $dbh->selectrow_array(
            "SELECT COUNT(*) FROM $groups WHERE Domain = 'UserDefined'"
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
    # Groups table is quoted via $groups (see quote_identifier above) because
    # GROUPS is a reserved word in MySQL 8.
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
            "SELECT COUNT(*) FROM $groups WHERE Domain = 'UserDefined'"
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
