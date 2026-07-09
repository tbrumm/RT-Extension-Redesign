package RT::Extension::FeedWidget;

our $VERSION = '1.0.2';

use strict;
use warnings;
use LWP::UserAgent;
use XML::LibXML;
use JSON;
use URI;
use Socket qw(getaddrinfo getnameinfo SOCK_STREAM NI_NUMERICHOST NIx_NOSERV);
use Encode qw(encode_utf8 decode);
use POSIX qw(strftime);

=head1 NAME

RT::Extension::FeedWidget - Dashboard widget for RSS/ATOM feed display with per-user configuration

=head1 DESCRIPTION

Adds a configurable RSS/ATOM feed reader widget to RT 6 dashboards. Each user
can configure their own list of feed URLs on the About Me preferences page.
Feed data is fetched server-side (avoids browser CORS restrictions) and cached
in the user's session.

=head1 INSTALLATION

    perl Makefile.PL
    make
    sudo make install

=head2 Register the plugin

Add to F</opt/rt6/etc/RT_SiteConfig.pm>:

    Plugin('RT::Extension::FeedWidget');

=head2 Add to HomepageComponents

In F</opt/rt6/etc/RT_SiteConfig.d/> create F<feedwidget.pm>:

    Set($HomepageComponents, [qw(
        QuickCreate Quicksearch MyAdminQueues
        RefreshHomepage
        FeedWidget
    )]);

=head2 Clear cache and restart

    sudo systemctl stop apache2
    sudo rm -rf /opt/rt6/var/mason_data/obj/*
    sudo systemctl start apache2

=head1 AUTHOR

Torsten Brumm

=head1 LICENSE

GNU General Public License v2

=cut

# -----------------------------------------------------------------------
# User feed configuration (stored as RT user attribute)
# -----------------------------------------------------------------------

sub GetUserFeeds {
    my ( $class, $user ) = @_;
    my $attr = $user->FirstAttribute('FeedWidgetFeeds');
    return [] unless $attr && $attr->Content;
    my $data = eval { from_json( $attr->Content, { utf8 => 1 } ) };
    return ref($data) eq 'ARRAY' ? $data : [];
}

sub SetUserFeeds {
    my ( $class, $user, $feeds ) = @_;
    my $json = to_json( $feeds, { utf8 => 1, pretty => 0 } );
    $user->SetAttribute( Name => 'FeedWidgetFeeds', Content => $json );
}

# -----------------------------------------------------------------------
# Feed fetching and parsing
# -----------------------------------------------------------------------

my $UA;

sub _ua {
    return $UA if $UA;
    $UA = LWP::UserAgent->new(
        agent   => 'RT-FeedWidget/' . $VERSION . ' (RT/' . $RT::VERSION . ')',
        timeout => 15,
        max_redirect => 5,
    );
    # Verify TLS certificates on HTTPS feeds (no MITM). If an internal feed uses
    # a self-signed cert, add its CA to the system trust store rather than
    # disabling verification here.
    $UA->ssl_opts( verify_hostname => 1 );
    _apply_proxy($UA);
    return $UA;
}

# Route feed fetches through the $FeedWidgetProxy config value when set,
# otherwise honour the process HTTP(S)_PROXY/NO_PROXY environment (the
# historical behaviour). Scoped to this widget's own UA, so the rest of RT's
# outbound traffic is unaffected. NO_PROXY is intentionally not applied to an
# explicit proxy: internal feed hosts are already refused by the SSRF guard
# below, so there is no "bypass proxy for internal feed" case to support.
sub _apply_proxy {
    my $ua = shift;
    my $proxy = RT->Config->Get('FeedWidgetProxy');
    if ( defined $proxy && length $proxy ) {
        $ua->proxy( [qw(http https)], $proxy );
    }
    else {
        $ua->env_proxy;
    }
}

# -----------------------------------------------------------------------
# SSRF guard
# -----------------------------------------------------------------------
# Refuse to fetch a feed whose host resolves into a private, loopback or
# link-local range. Without this, an authenticated user who saves an
# internal URL as a feed could turn the server-side fetch into an internal
# network probe. (Residual: DNS rebinding between this check and the actual
# connect is not covered — proportionate for an internal tool.)

sub _ip_is_blocked {
    my ($ip) = @_;
    return 1 unless defined $ip && length $ip;

    if ( $ip =~ /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/ ) {
        my @o = ( $1, $2, $3, $4 );
        return 1 if $o[0] == 0;                                  # 0.0.0.0/8
        return 1 if $o[0] == 10;                                 # 10/8
        return 1 if $o[0] == 127;                                # loopback
        return 1 if $o[0] == 169 && $o[1] == 254;               # link-local
        return 1 if $o[0] == 172 && $o[1] >= 16 && $o[1] <= 31;  # 172.16/12
        return 1 if $o[0] == 192 && $o[1] == 168;               # 192.168/16
        return 0;
    }

    my $lc = lc $ip;
    return _ip_is_blocked($1)
        if $lc =~ /^::ffff:(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$/;  # IPv4-mapped
    return 1 if $lc eq '::1' || $lc eq '::';                     # loopback / unspecified
    return 1 if $lc =~ /^fe80:/;                                 # link-local
    return 1 if $lc =~ /^f[cd][0-9a-f]{2}:/;                     # unique-local fc00::/7
    return 0;
}

sub _host_is_safe {
    my ($host) = @_;
    return 0 unless defined $host && length $host;

    my ( $err, @res ) = getaddrinfo( $host, '', { socktype => SOCK_STREAM } );
    return 0 if $err || !@res;        # unresolvable -> fail closed

    for my $ai (@res) {
        my ( $e2, $ipstr ) = getnameinfo( $ai->{addr}, NI_NUMERICHOST, NIx_NOSERV );
        return 0 if $e2;              # can't read address -> fail closed
        return 0 if _ip_is_blocked($ipstr);
    }
    return 1;
}

sub FetchFeed {
    my ( $class, $url, $max_items ) = @_;
    $max_items //= 10;

    my $host = eval { URI->new($url)->host };
    unless ( defined $host && length $host && _host_is_safe($host) ) {
        return { error => 'Feed host not allowed', items => [] };
    }

    my $res = eval { _ua()->get($url) };
    if ( $@ || !$res || !$res->is_success ) {
        my $err = $@ || ( $res ? $res->status_line : 'request failed' );
        return { error => $err, items => [] };
    }

    my $content = $res->decoded_content( charset => 'utf-8' );
    return _parse_feed( $content, $max_items );
}

sub _parse_feed {
    my ( $content, $max_items ) = @_;

    my $doc = eval {
        # no_network blocks external entities/DTDs (XXE/SSRF-via-entity);
        # libxml2's default entity-expansion limit handles "billion laughs".
        my $parser = XML::LibXML->new( recover => 2, no_network => 1 );
        $parser->parse_string($content);
    };
    return { error => 'XML parse error: ' . $@, items => [] } if $@;

    my $root = $doc->documentElement;
    return { error => 'Empty document', items => [] } unless $root;

    my $ns  = $root->namespaceURI // '';
    my $tag = $root->localname    // $root->nodeName;

    # Atom feed
    if ( $tag eq 'feed' || $ns =~ m{atom}i ) {
        return _parse_atom( $doc, $max_items );
    }

    # RSS 2.0 / RSS 1.0
    return _parse_rss( $doc, $max_items );
}

sub _text {
    my ($node) = @_;
    return '' unless $node;
    my $t = $node->textContent // '';
    $t =~ s/^\s+|\s+$//g;
    return $t;
}

sub _parse_atom {
    my ( $doc, $max_items ) = @_;

    my $xpc = XML::LibXML::XPathContext->new($doc);
    $xpc->registerNs( 'a', 'http://www.w3.org/2005/Atom' );

    my $title = _text( ( $xpc->findnodes('//a:feed/a:title') )[0] );
    $title ||= _text( ( $doc->findnodes('//*[local-name()="title"]') )[0] );

    my @entries = $xpc->findnodes('//a:entry');
    @entries = $doc->findnodes('//*[local-name()="entry"]') unless @entries;

    my @items;
    for my $entry ( @entries[ 0 .. $max_items - 1 ] ) {
        last unless $entry;

        my $item_title = _text( ( $xpc->findnodes( 'a:title', $entry ) )[0] );
        $item_title ||= _text( ( $entry->findnodes('*[local-name()="title"]') )[0] );

        my $link_node = ( $xpc->findnodes( 'a:link[@rel="alternate" or not(@rel)]', $entry ) )[0];
        $link_node ||= ( $entry->findnodes('*[local-name()="link"]') )[0];
        my $link = $link_node ? ( $link_node->getAttribute('href') || _text($link_node) ) : '';

        my $summary = _text( ( $xpc->findnodes( 'a:summary', $entry ) )[0] );
        $summary ||= _text( ( $xpc->findnodes( 'a:content', $entry ) )[0] );
        $summary ||= _text( ( $entry->findnodes('*[local-name()="summary"]') )[0] );
        $summary = _truncate($summary, 200);

        my $pub = _text( ( $xpc->findnodes( 'a:published|a:updated', $entry ) )[0] );
        $pub ||= _text( ( $entry->findnodes('*[local-name()="published"]|*[local-name()="updated"]') )[0] );

        push @items, {
            title   => $item_title,
            link    => $link,
            summary => $summary,
            pubdate => _format_date($pub),
        };
    }

    return { feed_title => $title, items => \@items };
}

sub _parse_rss {
    my ( $doc, $max_items ) = @_;

    my $title = _text( ( $doc->findnodes('//*[local-name()="channel"]/*[local-name()="title"]') )[0] );

    my @entries = $doc->findnodes('//*[local-name()="item"]');

    my @items;
    for my $entry ( @entries[ 0 .. $max_items - 1 ] ) {
        last unless $entry;

        my $item_title = _text( ( $entry->findnodes('*[local-name()="title"]') )[0] );

        my $link_node = ( $entry->findnodes('*[local-name()="link"]') )[0];
        my $link = $link_node ? _text($link_node) : '';
        # RSS link can be a sibling text node between elements
        if ( !$link && $link_node ) {
            my $sib = $link_node->nextSibling;
            $link = $sib->textContent if $sib;
        }

        my $summary = _text( ( $entry->findnodes('*[local-name()="description"]') )[0] );
        $summary = _truncate($summary, 200);

        my $pub = _text( ( $entry->findnodes('*[local-name()="pubDate"]|*[local-name()="date"]|*[local-name()="published"]') )[0] );

        push @items, {
            title   => $item_title,
            link    => $link,
            summary => _strip_html($summary),
            pubdate => _format_date($pub),
        };
    }

    return { feed_title => $title, items => \@items };
}

sub _strip_html {
    my ($html) = @_;
    return '' unless defined $html;
    $html =~ s/<[^>]+>//g;
    $html =~ s/&amp;/&/g;
    $html =~ s/&lt;/</g;
    $html =~ s/&gt;/>/g;
    $html =~ s/&quot;/"/g;
    $html =~ s/&#39;/'/g;
    $html =~ s/&nbsp;/ /g;
    $html =~ s/\s+/ /g;
    $html =~ s/^\s+|\s+$//g;
    return $html;
}

sub _truncate {
    my ( $text, $max ) = @_;
    $text = _strip_html($text);
    return $text if length($text) <= $max;
    return substr( $text, 0, $max ) . '...';
}

sub _format_date {
    my ($raw) = @_;
    return '' unless $raw;
    $raw =~ s/^\s+|\s+$//g;
    # Try to parse common date formats and return a short display date
    # RFC 2822: Mon, 01 Jan 2024 12:00:00 +0000
    # ISO 8601: 2024-01-01T12:00:00Z
    if ( $raw =~ /(\d{4})-(\d{2})-(\d{2})/ ) {
        return "$3.$2.$1";
    }
    if ( $raw =~ /(\d{1,2})\s+(\w+)\s+(\d{4})/ ) {
        return "$1. $2 $3";
    }
    return $raw;
}

1;
