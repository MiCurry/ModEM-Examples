#!/usr/bin/perl -w
#
#   Author: Anna Kelbert
#
#   Copyright (c) 2005  Anna Kelbert - All rights reserved
#
# Program suited to producing synthetic datasets from the <earth3d> output
#
# This is a complimentary (simpler) program to gsd.pl (Generate Synthetic Dataset),
# that generates not only the errors, but also the observatory distribution, using
# the data defined on the grid nodes. In contrast to gsd.pl, ise.pl will use the
# values in <fname>.<c|d>obs, computed at the exact observatory locations, to generate
# the respective synthetic dataset by introducing new errors. All information used by
# this program will be contained in <fname>.<c|d>obs.

use strict;
use Getopt::Long qw(:config no_ignore_case);;
use Math::Complex;
# use Math::Random;

# Package name.
my $my_package = 'ise.pl';

my $PERR=5;
my $DISTR='normal';
my $NAME='regress';
my $TYPE='';
my $BETA_0=0;
my $MAXLAT=90;
my $shorthelptext=<<EOF;
Usage: ise.pl [OPTIONS] modelfile.cdat [synthetic.cdat]
Type in 'ise.pl --help' for description of options
EOF
my $helptext=<<EOF;
<Introduce Synthetic Errors>
Usage: ise.pl [OPTIONS] modelfile.cdat [synthetic.cdat]
Mandatory arguments to long options are mandatory for short options too

 -p, --perror=PERR       Set percentage error imposed on data norm [$PERR]
 -d, --distr=DISTR       Error distribution [$DISTR]
 -e, --error=NAME        Error generated according to NAME [$NAME]
 -t, --type=TYPE         Data type info used for error generation [$TYPE]

 --lat=LAT               Do not include observatories at higher latitudes [$MAXLAT]
 --beta=BETA_0           Override the default value of beta_0 for this TYPE

 --verbose               Tell me which observatories are being ignored
 --coords                If specified, the output is the coordinates only
 --help                  display help and exit

The program introduces errors into a user-specified data file in the format
Line 1 : Label (will be replaced)
Line 2 : Label (will be dublicated in the output data file)
Line 3+: Period Code GM_Lon GM_Lat Real(km) Imag(km) [Error(km)]
The data is assumed to be the output [model].[c|d]dat of program <earth3d>.
Instead we create a synthetic data set with errors of chosen magnitude.

f(lat) = 1              beta_0        beta_1                [default]
       = tan(90-lat)           = 60          = 80           [TYPE= C]
       = sin(90-lat)           = 60          = 40           [TYPE= D]

Errors generated according to the following error specifications:

percent:

    NORM = sqrt(real^2+imag^2);
    ABSERR = NORM * PERR/100;

regress:

    ABSERR = beta_0 + beta_1 tan(|lat|)

Specifics of imposed error distributions (output newreal, newimag, error):

normal:    error = ABSERR * f(lat);
           newreal = real + N(0,ABSERR^2) * f(lat);
           newimag = imag + N(0,ABSERR^2) * f(lat);

floor:     error = max(ABSERR,error);
           newreal = real;
           newimag = imag

Do not specify type [-t], unless you want errors multiplied by a function.
EOF

my $help=0;
my $coords=0;
my $verbose=0;
my $parsed=GetOptions
  (
   "perror=f" => \$PERR, # will accept real value
   "distr=s" => \$DISTR, # will accept a string
   "error=s" => \$NAME, # will accept a string
   "type=s" => \$TYPE, # will accept a string
   "lat=f" => \$MAXLAT,
   "beta=f" => \$BETA_0,

   "verbose|V" => \$verbose,
   "coords" => \$coords,
   "help|?" => \$help,
  );


if(!$parsed){
  print STDERR $shorthelptext;
  exit(1);
}
if($help){
  print $helptext;
  exit(1);
}
die "Set percentage error >0 [$PERR]" unless $PERR>0;
die "Set a positive maximum latitude [$MAXLAT]" unless $MAXLAT>0;
die "Set a correct distribution [$DISTR]" unless ($DISTR=~/normal/)||($DISTR=~/floor/);
die "Set a correct error name [$NAME]" unless ($NAME=~/regress/)||($NAME=~/percent/);
die "Not a well-defined data type [$TYPE]" unless ($TYPE=~/^[Cc]/)||($TYPE=~/^[Dd]/)||($TYPE=~/^$/);

if(@ARGV==0){
  print STDERR "No files specified\n";
  print STDERR $shorthelptext;
  exit(1);
}
if(@ARGV>2){
  print STDERR "Too many files\n";
  print STDERR $shorthelptext;
  exit(1);
}

my ($infile,$outfile)=@ARGV;

print STDERR "TYPE = $TYPE\n";
my ($beta_0,$beta_1);
if($TYPE=~/^[Cc]/){
  ($beta_0,$beta_1) = (60,80);
} elsif($TYPE=~/^[Dd]/){
  ($beta_0,$beta_1) = (50,30);
} else {
  ($beta_0,$beta_1) = (60,80);
}
if($BETA_0) { $beta_0=$BETA_0; }

if($NAME=~/regress/){
  print STDERR "./$my_package -e $NAME -d $DISTR --lat $MAXLAT $infile [$beta_0 + $beta_1 * tan(|lat|)]\n";
} else {
  print STDERR "./$my_package -e $NAME -d $DISTR --lat $MAXLAT -p $PERR $infile\n";
}

unless(defined ($outfile)){
  print STDERR "Reading $infile...\n";
  $infile =~ /^(\S+)(\.)(\w)(\w+)$/;
  if ($coords){
    $outfile="$1.coords";
  }else{
    $outfile="$1_new.$3dat";
  }
  print STDERR "Output written to file $outfile\n";
}
################################################################
# Common variable definitions                                  #
################################################################

my %coord=(); # $coord{$code}
my %info=(); # @{$info{$per}}
my %freq=(); # $freq{$per}
my ($label,$label2);

################################################################
# Main block of subroutine calls                               #
################################################################

read_data($infile);

if($coords){
  print_obs($outfile);
  exit(1);
}

print_main($outfile);


################################################################
# Subroutines                                                  #
################################################################

sub read_data{
  my ($fname)=(@_);
  open(INFO, "$fname") or die("Can't open $fname: $!");
  $label=<INFO>;
  $label2=<INFO>;
  while(<INFO>){
    chomp;
    s/^\s+//; # remove first blank space if present
    if(/[a-z]/){next;}
    my @line  = split (/\s+/,$_);
    my ($per,$code,$lon,$lat,@value) = @line;

    if(abs($lat)>$MAXLAT){
      if($verbose){ print STDERR "Period $per: observatory $code will be ignored\n"; }
      next;
    }

    my ($real,$imag,$ferr);
    if((@value<2)||(@value>3)){
      print STDERR "Error in input file $fname: ",scalar @value," data entries\n";
      print "($per,$code,$lon,$lat,@value)";
      exit(1);
    } elsif(@value == 3){
      $ferr = $value[2];
    } else {
      $ferr = 0.0;
    }
    $real = $value[0];
    $imag = $value[1];

    my $resp_norm = sqrt($real*$real + $imag*$imag);

    my $err;
    if($NAME=~/percent/){
      $err = $resp_norm*$PERR/100;
    } else {
      $err = $beta_0 + $beta_1 * tan(abs($lat)*pi()/180);
    }

    if($TYPE=~/^[Cc]/){
      $err = $err * abs(tan((90.-$lat)*pi()/180));
    } elsif($TYPE=~/^[Dd]/){
      $err = $err * abs(sin((90.-$lat)*pi()/180));
    }

    my ($resp_real,$resp_imag);

    if($DISTR=~/normal/){
      my (@std) = gaussian_rand();
      $resp_real=$real + $std[0]*$err;
      $resp_imag=$imag + $std[1]*$err;
    } else {
      $resp_real=$real;
      $resp_imag=$imag;
      if($err<$ferr){ $err=$ferr; };
    }

    $resp_real = sprintf("%.4f", $resp_real);
    $resp_imag = sprintf("%.4f", $resp_imag);
    $err       = sprintf("%.4f", $err);

    if(exists($info{$per})){
      push @{$info{$per}},
	"$per $code $lon $lat $resp_real $resp_imag $err";
    }else{
      $info{$per}=
	[
	 "$per $code $lon $lat $resp_real $resp_imag $err"
	];
    };

    if(!exists($coord{$code})){
      my $colat = 90.0 - $lat;
      $coord{$code}="$code $colat $lon";
    }

   if(!exists($freq{$per})){
      my $freq  = 1/(60*60*24*$per);
      $freq{$per} = $freq;
    }
  }
  close INFO;
}

sub print_main{
  my ($fname)=(@_);
  {
    local  $"="\n";
    open OUT, ">$fname";
    if($NAME=~/regress/){
      print OUT "./$my_package -e $NAME -d $DISTR --lat $MAXLAT $infile [$beta_0 + $beta_1 * tan(|lat|)]\n";
    } else {
      print OUT "./$my_package -e $NAME -d $DISTR --lat $MAXLAT -p $PERR $infile\n";
    }
    print OUT "$label2";
    my $period;
    foreach $period(sort {$b<=>$a} keys %info){
      my @info=sort @{$info{$period}};
      print OUT "@info\n";
    }
    close OUT;
  }
}

sub print_obs{
  my ($fname)=(@_);
  {
    open OUT, ">$fname";
    print OUT "#./$my_package --coords $infile\n";
    print OUT scalar keys %coord,"\n";
    my $obs;
    foreach $obs(sort {$a cmp $b} keys %coord){
      print OUT "$coord{$obs}\n";
    }
    close OUT;
  }
}

sub chi_squared{
  my ($data,$response)=(@_);
  my ($c_real,$c_imag,$c_err)=split " ",$data;
  my ($cresp_real,$cresp_imag)=split " ",$response;
  my $tmp=(($c_real-$cresp_real)/$c_err)**2+(($c_imag-$cresp_imag)/$c_err)**2;
  return $tmp;
}


# the following subroutines are required to generate the errors

sub error_generator{
  my ($std,$code)=(@_); # standart deviation = sqrt(var)
  if (!($std)) {
    die "One of the C values is $std";
  }
  if ($std<0) {
    $std = - $std;
  }
  my $normal_error = gaussian_rand()*$std;
  if (!($code)) {
    return $normal_error;
  } else {
    return $normal_error/1000;
  }
#  return random_normal(1, 0, $cvalue);
}

sub gaussian_rand {
    my ($u1, $u2);  # uniformly distributed random numbers
    my $w;          # variance, then a weight
    my ($g1, $g2);  # gaussian-distributed numbers

    do {
        $u1 = 2 * rand() - 1;
        $u2 = 2 * rand() - 1;
        $w = $u1*$u1 + $u2*$u2;
    } while ( $w >= 1 );

    $w = sqrt( (-2 * log($w))  / $w );
    $g2 = $u1 * $w;
    $g1 = $u2 * $w;
    # return both if wanted, else just one
    return wantarray ? ($g1, $g2) : $g1;
}

sub exp_rand {
  my $u; # uniformly distributed random number
  my $e;
  $u = rand();
  $e = - log(1-$u);
  return $e;
}


