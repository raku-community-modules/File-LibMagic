use v6;
use lib 'lib';
use Test;

use File::LibMagic;

my $magic = File::LibMagic.new;
diag "new";
my %info = $magic.for-filename('/usr/include/magic.h');
diag "for-filename";
dd %info;

ok 1;

done-testing;
