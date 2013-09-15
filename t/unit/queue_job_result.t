#!/usr/bin/env perl

# mt-aws-glacier - Amazon Glacier sync client
# Copyright (C) 2012-2013  Victor Efimov
# http://mt-aws.com (also http://vs-dev.com) vs@vs-dev.com
# License: GPLv3
#
# This file is part of "mt-aws-glacier"
#
#    mt-aws-glacier is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    mt-aws-glacier is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use warnings;
use Test::More tests => 74;
use Test::Deep;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use App::MtAws::QueueJobResult;
use TestUtils;

warning_fatal();

my @codes = (JOB_RETRY, JOB_OK, JOB_WAIT, JOB_DONE);
my $coderef = sub { };

# partial_new, partial_full

cmp_deeply (App::MtAws::QueueJobResult->partial_new(a => 1, b => 2), bless { _type => 'partial', a => 1, b => 2 }, 'App::MtAws::QueueJobResult');
cmp_deeply (App::MtAws::QueueJobResult->full_new(a => 1, b => 2), bless { _type => 'full', a => 1, b => 2 }, 'App::MtAws::QueueJobResult');

{
	my ($r1, $r2) = map { { map { $_ => 1 } @$_ } } \@App::MtAws::QueueJobResult::valid_fields, [qw/code default_code task state job/];
	cmp_deeply $r1, $r2, "valid_fields should contain right data",
}

# state
cmp_deeply (App::MtAws::QueueJobResult->partial_new(state => 'abc'), state('abc'));

# job
cmp_deeply (App::MtAws::QueueJobResult->partial_new(job => 'abc'), job('abc'));


# task
{
	cmp_deeply
		[task('abc', $coderef)],
		[App::MtAws::QueueJobResult->partial_new(code => JOB_OK),
		App::MtAws::QueueJobResult->partial_new(task => {action => 'abc', cb => $coderef, args => {}})];
	cmp_deeply
		[task('abc', { z => 1}, $coderef)],
		[App::MtAws::QueueJobResult->partial_new(code => JOB_OK),
		App::MtAws::QueueJobResult->partial_new(task => {action => 'abc', cb => $coderef, args => {z => 1}})];

	my $attachment = "somedata";
	cmp_deeply [task('abc', { z => 1}, \$attachment, $coderef)],
	[App::MtAws::QueueJobResult->partial_new(code => JOB_OK),
	App::MtAws::QueueJobResult->partial_new(task => {action => 'abc', cb => $coderef, args => {z => 1}, attachment => \$attachment})];

	ok ! eval { task("something"); 1; }, "should complain with 1 arg";
	like $@, qr/^at least two args/, "should complain without task_action";

	ok ! eval { task('a', 'z'); 1; }, "should complain if second arg is not hashref";
	like $@, qr/^no code ref/, "should complain if second arg is not hashref";

	ok ! eval { task('a', 'z', $coderef); 1; }, "should complain if second arg is not hashref";
	like $@, qr/^task_args should be hashref/, "should complain if second arg is not hashref";

	ok ! eval { task('a', {z => 1 }); 1; }, "should complain without coderef";
	like $@, qr/^no code ref/, "should complain without coderef";

	ok ! eval { task('a', {z => 1 }, "scalar", $coderef); 1; }, "should complain if attachment is not reference";
	like $@, qr/^attachment is not reference to scalar/, "should complain if attachment is not reference";
};


# codes

{
	for (@codes) {
		like $_, qr/^MT_J_/;
		ok $_, "code should be true";
		ok App::MtAws::QueueJobResult::is_code($_);
		ok !App::MtAws::QueueJobResult::is_code("someprefix$_");
	}

	{
		my %h = map { $_ => 1 } @codes;
		is scalar keys %h, scalar @codes, "there should be no string duplicates";
	}
}

# parse_result

{
	ok ! eval { parse_result(); 1 };
	like $@, qr/^no data/;

	ok ! eval { parse_result(1); 1 };
	like $@, qr/^bad code/;

	ok ! eval { parse_result({}); 1 };
	ok ! eval { parse_result(sub {}); 1 };

	ok ! eval { parse_result(App::MtAws::QueueJobResult->full_new); 1 };
	like $@, qr/^should be partial/;

	ok ! eval { parse_result(JOB_OK); 1 };
	like $@, qr/^no task/, "should not allow sole JOB_OK ";

	for my $c (@codes) {
		ok ! eval { parse_result($c, task("mytask", sub {})); 1 };
		like $@, qr/^double data/, "should not allow cobmining code and task for code $c";
	}

	for my $field (@App::MtAws::QueueJobResult::valid_fields) {
		my $a1 = App::MtAws::QueueJobResult->partial_new($field => "somevalue1");
		my $a2 = App::MtAws::QueueJobResult->partial_new($field => "somevalue2");
		ok !eval { parse_result($a1, $a2); 1; };
		like $@, qr/^double data/, "should not allow double data";
	}


	# code and default_code
	cmp_deeply parse_result(
		App::MtAws::QueueJobResult->partial_new(default_code => JOB_WAIT),
		JOB_RETRY
	), App::MtAws::QueueJobResult->full_new(code => JOB_RETRY), "existing code should not be overwritten by default_code";

	cmp_deeply parse_result(
		App::MtAws::QueueJobResult->partial_new(default_code => JOB_WAIT),
	), App::MtAws::QueueJobResult->full_new(code => JOB_WAIT), "code should default to default_code";

	cmp_deeply(App::MtAws::QueueJobResult->full_new(code => JOB_OK, task => {action => "mytask", args => {}, cb => $coderef} ),
		parse_result(task("mytask", $coderef)), "should allow task");

	cmp_deeply(App::MtAws::QueueJobResult->full_new(code => JOB_OK, task => {action => "mytask", args => {}, cb => $coderef}, state => "somestate" ),
		parse_result(task("mytask", $coderef), state("somestate")), "should allow task+state");

	for my $c (grep { $_ ne JOB_OK } @codes) {
		cmp_deeply( App::MtAws::QueueJobResult->full_new(code => $c), parse_result($c), "should allow sole code $c" );
		cmp_deeply( App::MtAws::QueueJobResult->full_new(code => $c, state => "somestate"), parse_result($c, state("somestate")), "should allow code $c and state" );
	}
	cmp_deeply( App::MtAws::QueueJobResult->full_new(code => JOB_RETRY, state => "somestate"), parse_result(state("somestate")), "should allow sole state" );

}


1;
