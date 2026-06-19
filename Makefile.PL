use lib '.';
use inc::Module::Install;
RTx('RT-Extension-Redesign');
all_from('lib/RT/Extension/Redesign.pm');
license('gpl_2');
requires_rt('6.0.2');
rt_too_new('7.0.0');

# CPAN deps used directly by the extension (FeedWidget). XML::LibXML is NOT a
# core RT dependency, so declare it here or installs silently ship a broken
# FeedWidget (feed fetch + SaveFeeds.html die with "Can't locate XML/LibXML.pm").
requires('LWP::UserAgent');
requires('XML::LibXML');
requires('JSON');
requires('JSON::PP');

# bin/ is shipped into local/plugins/RT-Extension-Redesign/bin by RTx itself
# (it indexes bin/ as an install dir). Do NOT add install_script() — that routes
# the script to the system INSTALLSCRIPT dir (/usr/local/bin) and breaks `make
# install` on a non-root box.
sign(0);
WriteAll();
