package RT::Extension::FeedWidget;

our $VERSION = '1.0.0';

use strict;
use warnings;
use LWP::UserAgent;
use XML::LibXML;
use JSON;
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
    $UA->ssl_opts( verify_hostname => 0 );
    return $UA;
}

sub FetchFeed {
    my ( $class, $url, $max_items ) = @_;
    $max_items //= 10;

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
