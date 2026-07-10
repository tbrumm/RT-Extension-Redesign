package RT::Extension::Redesign;

our $VERSION = '0.31';

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
        Content => [ { Name => 'LoginShowPromo' }, { Name => 'FeedWidgetProxy' } ],
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
            FeedWidgetProxy => {
                Type            => 'SCALAR',
                Default         => '',
                Immutable       => 1,
                Widget          => '/Widgets/Form/String',
                WidgetArguments => {
                    Description => 'Outbound HTTP/HTTPS proxy URL used only for FeedWidget feed fetches, e.g. http://proxy:3128. Leave empty to honour the HTTP(S)_PROXY/NO_PROXY environment variables (default).',  # loc
                },
            },
        },
    );
}

# RedesignNewReplyBadge: per-user control of the "New Reply" badge in ticket
# lists (rendered by the RT__Ticket/ColumnMap/Once callback). A genuine per-user
# preference, so it uses an Overridable Widget shown on Prefs/Other.html under
# its own "Redesign" section (the SideBySideView TicketViewLayout pattern) rather
# than the Immutable RegisterPluginConfig path used for global options above.
#   all     - show on replies and on new tickets (Create) = current behaviour
#   replies - show only for an unseen Correspond/Comment, never for Create alone
#   off     - never show the badge
# The Default here is the single source of truth: active from Plugin('...') alone,
# overridable per user via Preferences. A bare hash assignment is safe even when
# RT is not initialised (standalone unit tests), so no eval guard is needed.
$RT::Config::META{'RedesignNewReplyBadge'} = {
    Type            => 'SCALAR',
    Section         => 'Redesign',   # loc
    Overridable     => 1,
    SortOrder       => 1,
    Widget          => '/Widgets/Form/Select',
    WidgetArguments => {
        Description => 'New Reply badge in ticket lists',   # loc
        Values      => [ 'all', 'replies', 'off' ],
        ValuesLabel => {
            all     => 'On replies and new tickets',        # loc
            replies => 'On replies only (not new tickets)', # loc
            off     => 'Never show',                        # loc
        },
    },
    Default => 'all',
};

# Front-end assets ship as external files under static/ and are registered here,
# never as inline <script>/<style> in Mason: RT6's <body hx-boost="true"> swaps
# the body on every navigation, so inline scripts and DOMContentLoaded listeners
# do not reliably re-run. The eval guard keeps the module loadable standalone
# (unit tests) where RT is not initialised.
if ( eval { RT->can('AddJavaScript') } ) {
    RT->AddJavaScript('redesign/redesign-global.js');
    RT->AddJavaScript('redesign/redesign-widgets.js');
    RT->AddJavaScript('redesign/redesign-ticket.js');
    RT->AddJavaScript('redesign/redesign-admin.js');
    RT->AddJavaScript('redesign/redesign-noauth.js');
    RT->AddJavaScript('redesign/redesign-prefs.js');
}

# Stylesheets ship as static assets too. redesign.css is the base; the per-area
# files carry the styles consolidated out of the former inline <style> blocks and
# are registered AFTER the base so they keep their original cascade precedence.
if ( eval { RT->can('AddStyleSheets') } ) {
    RT->AddStyleSheets('redesign/redesign.css');
    RT->AddStyleSheets('redesign/ticket-icons.css');
    RT->AddStyleSheets('redesign/redesign-widgets.css');
    RT->AddStyleSheets('redesign/redesign-admin.css');
    RT->AddStyleSheets('redesign/redesign-noauth.css');
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

# Run one stats query in isolation. A statement killed mid-flight (e.g. by a
# pt-kill watchdog) or any DB error yields a neutral value for just that stat
# instead of aborting the whole refresh. No reconnect is attempted: on a dead
# connection the remaining stats simply stay 0 rather than reconnecting in a
# tight loop.
sub _stat_scalar {
    my ( $dbh, $sql, @bind ) = @_;
    my @r = eval { $dbh->selectrow_array( $sql, undef, @bind ) };
    RT::Logger->error("Redesign stats query failed: $@") if $@;
    return $r[0];
}

sub _stat_rows {
    my ( $dbh, $sql, @bind ) = @_;
    my $r = eval { $dbh->selectall_arrayref( $sql, undef, @bind ) };
    RT::Logger->error("Redesign stats query failed: $@") if $@;
    return $r || [];
}

sub collect_stats {
    my $dbh = $RT::Handle->dbh;
    my %s;

    # `Groups` is a reserved word in MySQL 8; quote_identifier emits the right
    # identifier quoting for whichever DB driver is active (backticks on MySQL,
    # double quotes on PostgreSQL/Oracle/SQLite).
    my $groups = $dbh->quote_identifier('Groups');

    # --- Global (Scrips / Templates / Conditions / Actions) ---
    $s{global}{st} = _stat_scalar($dbh, "SELECT COUNT(*) FROM Scrips");
    $s{global}{sd} = _stat_scalar($dbh, "SELECT COUNT(*) FROM Scrips WHERE Disabled = 1");
    $s{global}{sg} = _stat_scalar($dbh,
        "SELECT COUNT(DISTINCT Scrip) FROM ObjectScrips WHERE ObjectId = 0");
    $s{global}{sq} = ($s{global}{st} // 0) - ($s{global}{sg} // 0);

    $s{global}{tt} = _stat_scalar($dbh, "SELECT COUNT(*) FROM Templates");
    $s{global}{tg} = _stat_scalar($dbh, "SELECT COUNT(*) FROM Templates WHERE ObjectId = 0");
    $s{global}{tq} = ($s{global}{tt} // 0) - ($s{global}{tg} // 0);

    $s{global}{ct} = _stat_scalar($dbh, "SELECT COUNT(*) FROM ScripConditions");
    $s{global}{at} = _stat_scalar($dbh, "SELECT COUNT(*) FROM ScripActions");
    $s{global}{$_} //= 0 for qw(st sd sg sq tt tg tq ct at);

    # --- Tools ---
    $s{tools}{ds} = _stat_scalar($dbh,
        "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 1)
         FROM information_schema.tables WHERE table_schema = DATABASE()");
    $s{tools}{cr} = _stat_scalar($dbh, "SELECT COUNT(*) FROM CustomRoles");
    $s{tools}{sp} = _stat_scalar($dbh,
        "SELECT COUNT(*) FROM Attributes WHERE Name = 'Crontool'");
    $s{tools}{$_} //= 0 for qw(ds cr sp);

    # --- Articles ---
    my $cl = _stat_rows($dbh, "SELECT Disabled, COUNT(*) FROM Classes GROUP BY Disabled");
    my %cld; $cld{$_->[0]} = $_->[1] for @$cl;
    $s{articles}{ca} = $cld{0} // 0;
    $s{articles}{ct} = ($cld{0} // 0) + ($cld{1} // 0);

    $s{articles}{at} = _stat_scalar($dbh, "SELECT COUNT(*) FROM Articles");
    # "Active" = article itself enabled AND its Class enabled (an article in a
    # disabled class is effectively unavailable, so it is not counted active).
    $s{articles}{aa} = _stat_scalar($dbh,
        "SELECT COUNT(*) FROM Articles a
         JOIN Classes c ON a.Class = c.id
         WHERE a.Disabled = 0 AND c.Disabled = 0");
    $s{articles}{$_} //= 0 for qw(ca ct aa at);

    # --- Assets ---
    my $rows = _stat_rows($dbh, "SELECT Status, COUNT(*) FROM Assets GROUP BY Status");
    my %by_status; $by_status{$_->[0]} = $_->[1] for @$rows;
    $s{assets}{aa} = $by_status{allocated} // 0;
    $s{assets}{ai} = $by_status{'in-use'}  // 0;
    $s{assets}{ad} = $by_status{deleted}   // 0;
    $s{assets}{ao} = 0;
    for my $st (keys %by_status) {
        next if $st eq 'allocated' || $st eq 'in-use' || $st eq 'deleted';
        $s{assets}{ao} += $by_status{$st};
    }
    $s{assets}{at} = $s{assets}{aa} + $s{assets}{ai}
                   + $s{assets}{ao} + $s{assets}{ad};

    my $cat = _stat_rows($dbh, "SELECT Disabled, COUNT(*) FROM Catalogs GROUP BY Disabled");
    my %catd; $catd{$_->[0]} = $_->[1] for @$cat;
    $s{assets}{ca} = $catd{0} // 0;
    $s{assets}{ct} = ($catd{0} // 0) + ($catd{1} // 0);
    $s{assets}{$_} //= 0 for qw(aa ai ad ao at ca ct);

    # --- Custom Fields ---
    my $cfrows = _stat_rows($dbh,
        "SELECT LookupType, COUNT(*) FROM CustomFields GROUP BY LookupType");
    my %by_type; $by_type{$_->[0]} = $_->[1] for @$cfrows;
    $s{cf}{ti} = $by_type{'RT::Queue-RT::Ticket'}                 // 0;
    $s{cf}{as} = $by_type{'RT::Catalog-RT::Asset'}                // 0;
    $s{cf}{us} = $by_type{'RT::User'}                             // 0;
    $s{cf}{ar} = $by_type{'RT::Class-RT::Article'}                // 0;
    $s{cf}{tr} = $by_type{'RT::Queue-RT::Ticket-RT::Transaction'} // 0;
    $s{cf}{to} = 0;
    $s{cf}{to} += $_ for values %by_type;
    # Any LookupType not broken out above (e.g. RT::Queue CFs on queues
    # themselves) so the per-type rows still add up to the total.
    $s{cf}{ot} = $s{cf}{to} - ($s{cf}{ti} + $s{cf}{as} + $s{cf}{us}
                             + $s{cf}{ar} + $s{cf}{tr});
    $s{cf}{$_} //= 0 for qw(ti as us ar tr to ot);

    # --- Login page ---
    # Groups table is quoted via $groups (see quote_identifier above) because
    # GROUPS is a reserved word in MySQL 8.
    $s{login}{priv} = _stat_scalar($dbh,
        "SELECT COUNT(gm.MemberId)
         FROM GroupMembers gm
         JOIN $groups g ON gm.GroupId = g.id
         JOIN Principals p ON gm.MemberId = p.id
         WHERE g.Domain = 'SystemInternal' AND g.Name = 'Privileged'
           AND p.PrincipalType = 'User' AND p.Disabled = 0");
    $s{login}{unpriv} = _stat_scalar($dbh,
        "SELECT COUNT(gm.MemberId)
         FROM GroupMembers gm
         JOIN $groups g ON gm.GroupId = g.id
         JOIN Principals p ON gm.MemberId = p.id
         WHERE g.Domain = 'SystemInternal' AND g.Name = 'Unprivileged'
           AND p.PrincipalType = 'User' AND p.Disabled = 0");
    $s{login}{groups}  = _stat_scalar($dbh,
        "SELECT COUNT(*) FROM $groups WHERE Domain = 'UserDefined'");
    $s{login}{queues}  = _stat_scalar($dbh,
        "SELECT COUNT(*) FROM Queues WHERE id > 0 AND Disabled = 0");
    $s{login}{tickets} = _stat_scalar($dbh,
        "SELECT COUNT(*) FROM Tickets WHERE id > 0 AND Status != 'deleted'");
    # Transactions is huge; an exact COUNT(*) is a full scan that a query
    # watchdog (pt-kill) may abort. Use the optimizer's row estimate from
    # information_schema instead -- instant, no scan, and accurate enough for a
    # data-volume figure on the public login page.
    $s{login}{txns} = _stat_scalar($dbh,
        "SELECT TABLE_ROWS FROM information_schema.TABLES
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'Transactions'");
    $s{login}{assets}   = _stat_scalar($dbh, "SELECT COUNT(*) FROM Assets");
    $s{login}{articles} = _stat_scalar($dbh, "SELECT COUNT(*) FROM Articles");
    $s{login}{$_} //= 0 for qw(priv unpriv groups queues tickets txns assets articles);

    # --- Admin overview (for Admin/index.html) ---
    # Groups table is quoted via $groups (see quote_identifier above) because
    # GROUPS is a reserved word in MySQL 8.
    my $q_rows = _stat_rows($dbh,
        "SELECT Disabled, COUNT(*) FROM Queues WHERE id > 0 GROUP BY Disabled");
    my %qd; $qd{$_->[0]} = $_->[1] for @$q_rows;
    $s{admin}{qa} = $qd{0} // 0;
    $s{admin}{qt} = ($qd{0} // 0) + ($qd{1} // 0);

    my $cf_rows = _stat_rows($dbh,
        "SELECT Disabled, COUNT(*) FROM CustomFields GROUP BY Disabled");
    my %cfd; $cfd{$_->[0]} = $_->[1] for @$cf_rows;
    $s{admin}{ca} = $cfd{0} // 0;
    $s{admin}{ct} = ($cfd{0} // 0) + ($cfd{1} // 0);

    $s{admin}{g} = _stat_scalar($dbh,
        "SELECT COUNT(*) FROM $groups WHERE Domain = 'UserDefined'");

    # Identify the Privileged/Unprivileged system groups by Domain+Name
    # (like the login section) rather than hard-coded group ids 4/5.
    my $u_rows = _stat_rows($dbh,
        "SELECT g.Name, COUNT(DISTINCT u.id)
         FROM Users u
         JOIN GroupMembers gm ON gm.MemberId = u.id
         JOIN $groups g ON gm.GroupId = g.id
         JOIN Principals p ON p.id = u.id
         WHERE g.Domain = 'SystemInternal'
           AND g.Name IN ('Privileged', 'Unprivileged')
           AND p.Disabled = 0 AND u.id > 2
         GROUP BY g.Name");
    my %ug; $ug{$_->[0]} = $_->[1] for @$u_rows;
    $s{admin}{up} = $ug{Privileged}   // 0;
    $s{admin}{uu} = $ug{Unprivileged} // 0;

    $s{admin}{ud} = _stat_scalar($dbh,
        "SELECT COUNT(*) FROM Principals
         WHERE Disabled = 1 AND PrincipalType = 'User' AND id > 2");

    # Classify each ticket by its queue's lifecycle, not a hard-coded status
    # list: a status can be active in one lifecycle and inactive in another,
    # custom lifecycles define their own statuses, and the initial status is
    # not always literally "new". Only count tickets in enabled queues.
    my $lc         = RT->Config->Get('Lifecycles')      || {};
    my $default_lc = RT->Config->Get('DefaultLifecycle') || 'default';

    my $t_rows = _stat_rows($dbh,
        "SELECT q.Lifecycle, t.Status, COUNT(*)
           FROM Tickets t JOIN Queues q ON t.Queue = q.id
          WHERE t.id > 0 AND q.Disabled = 0
          GROUP BY q.Lifecycle, t.Status");
    $s{admin}{tn} = $s{admin}{ta} = $s{admin}{tr} = $s{admin}{td} = 0;
    for my $row (@$t_rows) {
        my ($lcname, $status, $count) = @$row;
        $count ||= 0;
        if ($status eq 'deleted') { $s{admin}{td} += $count; next; }
        my $def = $lc->{ ($lcname && length $lcname) ? $lcname : $default_lc }
               // $lc->{$default_lc} // {};
        my %in;
        for my $set (qw(initial active inactive)) {
            $in{$_} = $set for @{ $def->{$set} || [] };
        }
        my $cls = $in{$status} // 'active';   # unknown status -> active
        if    ($cls eq 'initial')  { $s{admin}{tn} += $count; }
        elsif ($cls eq 'inactive') { $s{admin}{tr} += $count; }
        else                       { $s{admin}{ta} += $count; }
    }
    $s{admin}{$_} //= 0 for qw(qa qt ca ct g up uu ud tn ta tr td);

    $s{refreshed_at} = time();
    return \%s;
}

=head2 NewReplyBadgeTxn($ticket, $mode)

Decide whether the "New Reply" badge should be shown for C<$ticket> in a ticket
list, for the identity C<< $ticket->CurrentUser >>. C<$mode> is the per-user
C<RedesignNewReplyBadge> preference (C<all>/C<replies>/C<off>; anything else is
treated as C<all>). Returns the C<RT::Transaction> the badge should link to
(with C<&MarkAsSeen=1>), or C<undef> when no badge belongs there.

Two gates: (1) the ticket's last updater is a Requestor or Cc watcher and is
not the current viewer; (2) there is an unseen transaction. In C<all> mode
gate 2 is core C<SeenUpTo> (a new ticket's C<Create> counts). In C<replies>
mode gate 2 is an unseen C<Correspond>/C<Comment> only, so a brand-new ticket
does not trigger it. Watcher membership is tested by principal identity
(C<< $ticket->IsWatcher >>), never by email-string matching.

=cut

sub NewReplyBadgeTxn {
    my ( $class, $ticket, $mode ) = @_;
    $mode = 'all' unless defined $mode && ( $mode eq 'off' || $mode eq 'replies' );
    return undef if $mode eq 'off';

    my $last = $ticket->LastUpdatedByObj;
    return undef unless $last && $last->id;

    # No badge for the viewer's own last update (uniform for Requestor and Cc).
    return undef if $last->id == $ticket->CurrentUser->id;

    # Gate 1: the last updater is a Requestor or Cc watcher — tested by principal
    # identity, so a subaddress or an address that is a substring of another
    # watcher's address can never cause a false match.
    my $pid = $last->PrincipalId;
    my $last_is_watcher =
           $ticket->IsWatcher( Type => 'Requestor', PrincipalId => $pid )
        || $ticket->IsWatcher( Type => 'Cc',        PrincipalId => $pid );
    return undef unless $last_is_watcher;

    return $mode eq 'replies'
        ? $class->_first_unseen_message($ticket)
        : ( $ticket->SeenUpTo || undef );
}

# First unseen Comment/Correspond by another user, honouring the
# User-<uid>-SeenUpTo cutoff. Mirrors core RT::Ticket::SeenUpTo but excludes the
# Create transaction, so "replies only" mode never fires on a brand-new ticket.
sub _first_unseen_message {
    my ( $class, $ticket ) = @_;
    my $uid  = $ticket->CurrentUser->id;
    my $attr = $ticket->FirstAttribute( "User-${uid}-SeenUpTo" );
    return undef if $attr && $attr->Content gt $ticket->LastUpdated;

    my $txns = $ticket->Transactions;
    $txns->Limit( FIELD => 'Type', OPERATOR => 'IN',
                  VALUE => [ 'Comment', 'Correspond' ] );
    $txns->Limit( FIELD => 'Creator', OPERATOR => '!=', VALUE => $uid );
    $txns->Limit( FIELD => 'Created', OPERATOR => '>', VALUE => $attr->Content )
        if $attr;
    return $txns->First;
}

=head2 PriorityInfo(\%map, $num)

Given a C<%PriorityAsString> label-to-threshold map and a numeric priority,
return C<< { label, index, count } >>: the highest label whose threshold is
C<< <= $num >>, its 0-based position in the map sorted ascending by threshold,
and the number of levels. Returns C<undef> for an empty/undef map or a value
below the lowest threshold.

=cut

sub PriorityInfo {
    my ( $map, $num ) = @_;
    return undef unless ref $map eq 'HASH' && keys %$map;
    return undef unless defined $num && length $num;

    my @labels = sort { $map->{$a} <=> $map->{$b} } keys %$map;

    my $label;
    for my $l ( reverse @labels ) {
        if ( $num >= $map->{$l} ) { $label = $l; last }
    }
    return undef unless defined $label;

    my %index_of = map { $labels[$_] => $_ } 0 .. $#labels;
    return { label => $label, index => $index_of{$label}, count => scalar @labels };
}

=head2 PriorityAutoColor($index, $count) / ContrastText($color)

C<PriorityAutoColor> maps a 0-based position within C<$count> priority levels
to a colour on a green(low)->red(high) HSL gradient, so colouring follows
severity rather than label spelling and adapts to any number of levels.
C<ContrastText> picks black or white for legible text on a C<#rrggbb>
background (relative luminance); a non-hex value defaults to white.

=cut

sub PriorityAutoColor {
    my ( $index, $count ) = @_;
    $count = 1 if !$count || $count < 1;
    $index = 0 unless defined $index && $index > 0;
    $index = $count - 1 if $index > $count - 1;

    my $frac = $count > 1 ? $index / ( $count - 1 ) : 0;
    my $hue  = 120 * ( 1 - $frac );          # 120 = green .. 0 = red
    return _hsl_to_hex( $hue, 0.65, 0.45 );
}

sub _hsl_to_hex {
    my ( $h, $s, $l ) = @_;
    my $c  = ( 1 - abs( 2 * $l - 1 ) ) * $s;
    my $hp = $h / 60;
    my $x  = $c * ( 1 - abs( ( $hp - 2 * int( $hp / 2 ) ) - 1 ) );
    my ( $r, $g, $b ) =
          $hp < 1 ? ( $c, $x, 0 )
        : $hp < 2 ? ( $x, $c, 0 )
        : $hp < 3 ? ( 0, $c, $x )
        : $hp < 4 ? ( 0, $x, $c )
        : $hp < 5 ? ( $x, 0, $c )
        :           ( $c, 0, $x );
    my $mm = $l - $c / 2;
    return sprintf '#%02x%02x%02x',
        int( ( $r + $mm ) * 255 + 0.5 ),
        int( ( $g + $mm ) * 255 + 0.5 ),
        int( ( $b + $mm ) * 255 + 0.5 );
}

sub ContrastText {
    my ($color) = @_;
    return '#ffffff' unless defined $color && $color =~ /\A#([0-9a-fA-F]{6})\z/;
    my ( $r, $g, $b ) = map { hex } unpack 'A2A2A2', $1;
    my $lum = ( 0.299 * $r + 0.587 * $g + 0.114 * $b ) / 255;
    return $lum > 0.6 ? '#000000' : '#ffffff';
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
