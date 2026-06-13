use lib '.';
use inc::Module::Install;
RTx('RT-Extension-Redesign');
license('gpl_2');
author('Torsten Brumm');
requires_rt('6.0.2');
rt_too_new('7.0.0');

# CPAN deps used directly by the extension (FeedWidget). XML::LibXML is NOT a
# core RT dependency, so declare it here or installs silently ship a broken
# FeedWidget (feed fetch + SaveFeeds.html die with "Can't locate XML/LibXML.pm").
requires('LWP::UserAgent');
requires('XML::LibXML');
requires('JSON');
requires('JSON::PP');
install_script('bin/rt-redesign-stats-refresh');
sign(0);
WriteAll();
