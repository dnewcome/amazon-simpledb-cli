#!/usr/bin/perl -wT
use strict;

=head1 NAME

simpledb - Amazon SimpleDB command line interface

=head1 SYNOPSIS

 simpledb [opts] create-domain DOMAIN
 simpledb [opts] delete-domain DOMAIN
 simpledb [opts] list-domains

 simpledb [opts] put         DOMAIN ITEM [NAME=VALUE]...
 simpledb [opts] put-replace DOMAIN ITEM [NAME=VALUE]...
 simpledb [opts] get         DOMAIN ITEM [NAME]...
 simpledb [opts] delete      DOMAIN ITEM [NAME[=VALUE]]...

 simpledb [opts] query DOMAIN EXPRESSION

=head1 OPTIONS

 --help         Print help and exit.

 --aws-access-key-id KEY
                AWS access key id
                [Defaults to $AWS_ACCESS_KEY_ID environment variable]

 --aws-secret-access-key SECRETKEY
                AWS secret access key
                [Defaults to $AWS_SECRET_ACCESS_KEY environment variable]

 --max COUNT
                Maximum number of domains/items to retrieve and list.
                [Defaults to all]

 --separator STRING
                Separator between attribute name and value.
                [Defaults to equals (=)]

=head1 ARGUMENTS

 DOMAIN         Domain name
 ITEM           Item name
 NAME           Attribute name
 VALUE          Attribute value
 EXPRESSION     SimpleDB query expression

=head1 DESCRIPTION

This utility provides a simple command line interface to most Amazon
SimpleDB (SDB) actions.

=head1 EXAMPLES

# The following examples assume you have set these environment variables:

  export AWS_ACCESS_KEY_ID=...
  export AWS_SECRET_ACCESS_KEY=...

# Create a new SimpleDB domain:

  simpledb create-domain mydomain

# List the domains for this account:

  simpledb list-domains

# Create some items with attribute name=value pairs:

  simpledb put mydomain item1 key1=valueA key2=value2 x=why

  simpledb put mydomain item2 key1=valueB key2=value2 y=zee

# Add another value for an attribute on an item:

  simpledb put mydomain item2 y=zed when=now who=you

# Replace all values for specific attributes on an item:

  simpledb put-replace mydomain item1 key1=value1 newkey=newvalue

# Delete all values for specific attributes on an item:

  simpledb delete mydomain item1 x

# Delete specific values for specific attributes on an item:

  simpledb delete mydomain item2 who=you

# List all of the item names:

  simpledb query mydomain

# List all of the item names matching a given query:

  simpledb query mydomain "['key2'='value2']"

  simpledb query mydomain "['key2'='value2'] intersection ['y'='zee']"

# List all attributes on an item:

  simpledb get mydomain item1

  simpledb get mydomain item2

# List specific attributes on an item:

  simpledb get mydomain item2 key2 y

# Delete the entire SimpleDB domain including all items and attributes:

  simpledb delete-domain mydomain

=head1 ENVIRONMENT

 AWS_ACCESS_KEY_ID
                Default AWS access key id

 AWS_SECRET_ACCESS_KEY
                Default AWS secret access key

=head1 FILES

 $HOME/.awssecret
		If the above fail, then the keys are sought here in the
		format expected by the "aws" toolkit (one per line):
			access_key_id
			secret_access_key

 /etc/passwd-s3fs
		If all of the above fail, then the keys are sought
		here in the format expected by s3fs (colon separated):
			access_key_id:secret_access_key

=head1 INSTALLATION

BEWARE! The installation of dependencies is somewhat messy with this
release and may require some understanding of how Perl works!

This tool depends on the following Perl modules from CPAN:

  Getopt::Long
  Pod::Usage
  Digest::SHA1
  Digest::HMAC
  XML::Simple

You can install them using the "cpan" command on many Linux distros:

  sudo cpan Getopt::Long Pod::Usage Digest::SHA1 Digest::HMAC XML::Simple

This tool also depends on the Amazon::SDB modules provided by Amazon
(not the one in CPAN).  Amazon's modules can be found here:

  http://developer.amazonwebservices.com/connect/entry.jspa?externalID=1136

Here is how I installed them.

  curl -Lo amazon-simpledb-perl-library.zip \
    http://amazon-simpledb-perl-library.notlong.com

  unzip amazon-simpledb-perl-library.zip

  sitelib=$(perl -MConfig -le 'print $Config{sitelib}')
  sudo scp -r amazon-simpledb-*-perl-library/src/Amazon $sitelib

Finally, this command line interface can be installed with:

  sudo curl -Lo /usr/local/bin/simpledb http://simpledb-cli.notlong.com
  sudo chmod +x /usr/local/bin/simpledb

=head1 SEE ALSO

Latest versions of this script available from the Google Code project:
http://code.google.com/p/amazon-simpledb-cli/

Amazon SimpleDB (SDB)
http://www.amazon.com/SimpleDB-AWS-Service-Pricing/b/?node=342335011

Amazon SimpleDB Developer Guide
http://docs.amazonwebservices.com/AmazonSimpleDB/2007-11-07/DeveloperGuide/

sdbShell (another SimpleDB command line interface by David Kavanagh)
http://code.google.com/p/typica/

=head1 CAVEATS

As currently written this tool does not support keys containing equal
signs (=).

Output will be difficult to parse if the values contain newlines.

=head1 HISTORY

 2008-06-09 Eric Hammond <ehammond@thinksome.com>
 - Fallback to finding keys in $HOME/.awssecret or /etc/passwd-s3fs

 2008-06-03 Eric Hammond <ehammond@thinksome.com>
 - Completed --max option
 - bugfix: Corrected --aws-secret-access-key option spelling

 2008-05-26 Eric Hammond <ehammond@thinksome.com>
 - Original release

=cut

BEGIN { # Set envariables for -T tainting.
  $ENV{'PATH'}      = '/bin:/usr/bin';
  delete @ENV{'IFS', 'CDPATH', 'ENV', 'BASH_ENV'};
}
BEGIN { # Extract path and program name.
  use vars qw($path $prog);
  $0 =~ m%(.*)[/\\]([^/\\]*)%;
  ($path, $prog) = ($1 || '.', $2 || $0);
}

use Getopt::Long;
use Pod::Usage;
use Amazon::SimpleDB::Client;

my %METHODS = (
  'create-domain' => \&create_domain,
  'delete-domain' => \&delete_domain,
  'list-domains'  => \&list_domains,
  'put'           => \&put_attributes,
  'put-replace'   => \&put_replace_attributes,
  'get'           => \&get_attributes,
  'delete'        => \&delete_attributes,
  'query'         => \&query,
);

my $help        = 0;
my $aws_access_key_id     = $ENV{AWS_ACCESS_KEY_ID};
my $aws_secret_access_key = $ENV{AWS_SECRET_ACCESS_KEY};
my $replace               = 0;
my $max                   = undef;
my $separator             = '=';

Getopt::Long::config('no_ignore_case');
GetOptions(
           'help|?'                  => \$help,
           'aws-access-key-id=s'     => \$aws_access_key_id,
           'aws-secret-access-key=s' => \$aws_secret_access_key,
           'replace'                 => \$replace,
           'max=s'                   => \$max,
           'separator=s'             => \$separator,
          )
  or pod2usage(2);

pod2usage(1) if $help;

if ( not $aws_access_key_id and not $aws_secret_access_key ) {
  # Try reading $HOME/.awssecret in case the keys are there.
  if ( open(AWSSECRET, "< $ENV{HOME}/.awssecret") ) {
    chomp($aws_access_key_id     = <AWSSECRET>);
    chomp($aws_secret_access_key = <AWSSECRET>);
    close(AWSSECRET);
  # Try reading /etc/passwd-s3fs in case the keys are there.
  } elsif ( open(S3FS, "< /etc/passwd-s3fs") ) {
    chomp(($aws_access_key_id, $aws_secret_access_key) = split(':', <S3FS>));
    close(S3FS);
  }
}

die "$prog: ERROR: Specify --aws-access-key-id and --aws-secret-access-key\n"
  unless $aws_access_key_id and $aws_secret_access_key;

my $sdb = Amazon::SimpleDB::Client->new(
  $aws_access_key_id,
  $aws_secret_access_key,
);

my $command = shift(@ARGV) || pod2usage(1);
my $method = $METHODS{$command}
  || die "$prog: Unrecognized command: $command\n";

eval { &$method($sdb, @ARGV); };
error("$prog: ERROR: Running '$command @ARGV':", $@) if $@;

exit 0;

sub create_domain {
  my ($sdb, $domain_name) = @_;

  my $response = $sdb->createDomain({
    DomainName => $domain_name,
  });
}

sub list_domains {
  my ($sdb) = @_;

  my $next_token;
  my $count = 0;
  do {
    my $response = $sdb->listDomains({
      ($next_token ? (NextToken          => $next_token) : ()),
      ($max        ? (MaxNumberOfDomains => $max)        : ()),
    });

    my $domain_name_list = $response->getListDomainsResult->getDomainName;
    print defined $_ ? "$_\n" : '' for @$domain_name_list;
    $next_token = $response->getListDomainsResult->getNextToken
  } while ( $next_token and ++$count <= $max);
}

sub delete_domain {
  my ($sdb, $domain_name) = @_;

  my $response = $sdb->deleteDomain({
    DomainName => $domain_name,
  });
}

sub put_replace_attributes {
  $replace = 1;
  goto &put_attributes;
}

sub put_attributes {
  my ($sdb, $domain_name, $item_name, @pairs) = @_;

  my $response = $sdb->putAttributes({
    DomainName => $domain_name,
    ItemName   => $item_name,
    Attribute  => pairs_to_attributes(\@pairs, 1),
  });
}

sub delete_attributes {
  my ($sdb, $domain_name, $item_name, @pairs) = @_;

  my $response = eval {
    $sdb->deleteAttributes({
      DomainName => $domain_name,
      ItemName   => $item_name,
      Attribute  => pairs_to_attributes(\@pairs, 0),
    });
  };
}

sub get_attributes {
  my ($sdb, $domain_name, $item_name, @attribute_names) = @_;

  my $response = $sdb->getAttributes({
    DomainName => $domain_name,
    ItemName => $item_name,
    DomainName => $domain_name,
    ItemName   => $item_name,
    AttributeName => \@attribute_names,
  });
  my $attribute_list = $response->getGetAttributesResult->getAttribute;
  print $_->getName ? ($_->getName, $separator, $_->getValue, "\n") : ''
    for @$attribute_list;
}

sub query {
  my ($sdb, $domain_name, $query_expression) = @_;

  my $next_token;
  my $count = 0;
  do {
    my $response = $sdb->query({
      DomainName                       => $domain_name,
      QueryExpression                  => $query_expression,
      ($next_token ? (NextToken        => $next_token) : ()),
      ($max        ? (MaxNumberOfItems => $max)        : ()),
    });
    my $item_name_list = $response->getQueryResult->getItemName;
    print defined $_ ? "$_\n" : '' for @$item_name_list;
    $next_token = $response->getQueryResult->getNextToken
  } while ( $next_token and ++$count <= $max);
}

sub pairs_to_attributes {
  my ($pairs, $with_replace) = @_;

  my @attributes = ();
  for my $pair ( @$pairs ) {
    my ($name, $value) = split(/$separator/, $pair, 2);
    push @attributes, {
      Name                      => $name,
      Value                     => $value,
      ($with_replace ? (Replace => $replace ? 'true' : '') : ()),
    };
  }
  return \@attributes;
}

sub error {
  my ($message, $exception) = @_;

  if ( ref $exception eq "Amazon::SimpleDB::Exception" ) {
    $message .= " ".$exception->getMessage()."\n";
  } else {
    $message .= " $@\n";
  }
  die $message;
}
