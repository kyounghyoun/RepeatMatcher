#!/usr/bin/perl

=head1 NAME

extendRepeatConsensus.pl

=head1 DESCRIPTION

Iterative program to extend the borders in for a RepeatModeler consensus.

=head1 USAGE

    perl extendRepeatConsensus.pl [PARAM]

    Parameter     Description                                       Default
    -i --in       Consensus Fasta
    -g --genome   Genome Fasta
    -o --out      Output fasta
    -s --size     Step size per iteration                           [       8]
    -z --maxn     Maximal number of no-bases in extension           [       2]
    -w --win      Extension window                                  [      50]
    -t --temp     Temporary file names                              [    temp]
    -b --stop     Stop extension after this N bases                 [     100]
    -a --auto     Run auto mode (non-interactive)
    --no3p        Don't extend to 3'
    --no5p        Don't extend to 5'

    Search engine options
    -e --engine   Alignment engine (rmblast, wublast)               [ wublast]
    -x --matrix   Score matrix                                      [wumatrix]
    -c --score    Minimal score                                     [     200]
    -n --numseqs  Maximal number of sequences to try extending      [     200]
    -m --minseqs  Minimal number of sequences to continue extending [       3]
    -l --minlen   Minimal length of sequences                       [     100]
    -u --evalue   Maximal e-value                                   [   1e-10]
    -p --proc     Total threats to use in search                    [       4]
    -r --region   Define a region as additional seed in search,
                  the coordinates are 1b: 1,100
    --search_ext  Search again if extension > N                     [     100]
    --mult_hits   Stop is search hits > N times                     [       5]
    
    Cross_match options
    -d --div      Divergence level (14,18,20,25)                    [      14]
    --minscore    Cross_match minscore                              [     200]
    --minmatch    Cross_match minmatch                              [       7]
    
    Other options
    --editor      Use this editor (vi, emacs, pico, nano)           [   emacs]
    --pager       Use this command to view files (less, more)       [    less]
    -h --help     Print this screen and exit
    -v --verbose  Verbose mode on
    --version     Print version and exit

=head1 EXAMPLES

    perl extendRepeatConsensus.pl -i repeat.fa -g genome.fa -o new_repeat.fa

=head1 AUTHOR

Juan Caballero, Institute for Systems Biology @ 2012

=head1 CONTACT

jcaballero@systemsbiology.org

=head1 LICENSE

This is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with code.  If not, see <http://www.gnu.org/licenses/>.

=cut

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use lib './lib';
use NCBIBlastSearchEngine;
use WUBlastSearchEngine;
use SearchEngineI;
use SearchResultCollection;


# Default parameters
my $help     = undef;
my $verbose  = undef;
my $version  = undef;
my $in       = undef;
my $genome   = undef;
my $out      = undef;
my $auto     = undef;
my %conf     = ('size'      => 8,
                'engine'    => 'wublast',
                'numseq'    => 200,
                'minseq'    => 3,
                'minlen'    => 100,
                'div'       => 14,
                'maxn'      => 2,
                'win'       => 50,
                'no3p'      => 0,
                'no5p'      => 0,
                'temp'      => 'temp',
                'minmatch'  => 7,
                'minscore'  => 200,
                'evalue'    => 1 / 1e10,
                'proc'      => 4,
                'search'    => 1,
                'stop'      => 100,
                'matrix'    => 'wumatrix',
                'region'    => 0,
                'searchext' => 100,
                'multext'   => 5,
                'realiter'  => 0,
                'iter'      => 0,
                'extsize'   => 0
                );

# Main variables
my $our_version = 0.1;
my $pager       = 'less'; # or more
my $editor      = 'emacs'; # or vi, emacs, nano, pico, ...
my $linup       = './Linup';
my $rmblast     = '/usr/local/rmblast/bin/rmblastn';
my $makeblastdb = '/usr/local/rmblast/bin/makeblastdb';
my $wublast     = '/usr/local/wublast/blastn';
my $xdformat    = '/usr/local/wublast/xdformat';
my $matrix_dir  = './Matrices';
my $cross_match = '/usr/local/bin/cross_match';
my $new         = '';
my %genome      = ();
my %genome_len  = ();
my ($searchResults, $status, $Engine, $matrix, $proc, $evalue);

# Calling options
GetOptions(
    'h|help'            => \$help,
    'v|verbose'         => \$verbose,
    'version'           => \$version,
    'i|in=s'            => \$in,
    'o|out=s'           => \$out,
    'g|genome=s'        => \$genome,
    'a|auto'            => \$auto,
    'editor:s'          => \$editor,
    'pager:s'           => \$pager,
    'd|divergence:i'    => \$conf{'div'},
    's|size:i'          => \$conf{'size'},
    'l|minlen:i'        => \$conf{'minlen'},
    'e|engine:s'        => \$conf{'engine'},
    't|temp:s'          => \$conf{'temp'},
    'n|numseq:i'        => \$conf{'numseq'},
    'm|minseq:i'        => \$conf{'minseq'},
    'z|maxn:i'          => \$conf{'maxn'},
    'w|win:i'           => \$conf{'win'},
    'minscore:i'        => \$conf{'minscore'},
    'minmatch:i'        => \$conf{'minmatch'},
    'x|matrix:s'        => \$conf{'matrix'},
    'no3p'              => \$conf{'no3p'},
    'no5p'              => \$conf{'no5p'},
    'b|stop:i'          => \$conf{'stop'},
    'p|proc:i'          => \$conf{'proc'},
    'r|region:s'        => \$conf{'region'},
    'searchext:i'       => \$conf{'searchext'},
    'multiext:i'        => \$conf{'multiext'}
) or pod2usage(-verbose => 2);
printVersion()           if  (defined $version);
pod2usage(-verbose => 2) if  (defined $help);
pod2usage(-verbose => 2) if !(defined $in);
pod2usage(-verbose => 2) if !(defined $out);
pod2usage(-verbose => 2) if !(defined $genome);

$matrix = $conf{'matrix'};
$proc   = $conf{'proc'};
$evalue = $conf{'evalue'};

if ($conf{'engine'} eq 'wublast') {
    $Engine = WUBlastSearchEngine->new(pathToEngine => $wublast);
    $Engine->setMatrix("$matrix_dir/wublast/nt/$matrix");
    $Engine->setAdditionalParameters("-cpus $proc");
}
elsif ($conf{'engine'} eq 'rmblast') {
    $Engine = NCBIBlastSearchEngine->new(pathToEngine => $rmblast);
    $Engine->setMatrix("$matrix_dir/ncbi/nt/$matrix");
    $Engine->setAdditionalParameters("-num_threads $proc");
}
else { 
    die "search engine not supported: $conf{'engine'}\n"; 
}

checkIndex($conf{'engine'}, $genome);
my $cm_param    = checkDiv($conf{'div'});
my ($lab, $rep) = readFasta($in);
my $len_orig    = length $rep;

loadGenome($genome);

###################################
####        M A I N            ####
###################################
while (1) {
    $conf{'iter'}++;
    $conf{'realiter'}++;
    print "ITER #$conf{'realiter'}\n";
    warn "extending repeat\n" if (defined $verbose);
    if ($conf{'search'} == 1) {
        $new = extendRepeat($rep);
    }
    else {
        $new = extendRepeatNoSearch($rep, $conf{'iter'});
    }
    
    my $len_old  = length $rep;
    my $len_new  = length $new;
    $conf{'extsize'}  += $len_old - $len_new;
    if ($conf{'extsize'} >= $conf{'searchext'}) {
        $conf{'iter'}     = 0;
        $conf{'extsize'}  = 0;
        $conf{'search'}   = 1;
        $conf{'no5p'}     = 0;
        $conf{'no3p'}     = 0;
    }
    last if ($len_old == $len_new or $len_new >= ($len_orig + $conf{'stop'}));
    $rep = $new;
    next if (defined $auto);
    
    my $res;
    my $file = $conf{'temp'};
    my ($left, $right) = readBlocks("$file.ali");
    
    if ($conf{'no5p'} == 0) {
        open(my $less, '|-', $pager, '-e') || die "Cannot pipe to $pager: $!";
        print $less "LEFT SIDE>\n";
        print $less $left;
        close($less);
    }
    if ($conf{'no3p'} == 0) {
        open(my $less, '|-', $pager, '-e') || die "Cannot pipe to $pager: $!";
        print $less "RIGHT SIDE>\n";
        print $less $right;
        close($less);
    }
    
    print "SELECT: [Stop|Continue|Modify|Edit] ";
    $res = <>;
    chomp $res;
    last if ($res =~ m/^s/i);
    next if ($res =~ m/^c/i);
    
    if ($res =~ m/m/i) {
        print "Changing parameters:\n";
        foreach my $param (sort keys %conf) {
            next if ($param =~ m/proc|matrix|engine/);
            print "   $param [", $conf{$param}, "] : ";
            $res = <>; 
            chomp $res; 
            $conf{$param} = $res if ($res =~ m/\w/);
        }
    }
    
    if ($res =~ m/e/i) {
        my $file = $conf{'temp'} . ".edit";
        printFasta("$lab\n", $rep, $file);
        system ("$editor $file");
        ($lab, $rep) = readFasta($file);
    }
}
my $ext = (length $new) - $len_orig;
printFasta("$lab | extended $ext bases", $new, $out);

###################################
####   S U B R O U T I N E S   ####
###################################
sub printVersion {
    print "$0 $our_version\n";
    exit 1;
}

sub readFasta {
    my $file = shift @_;
    warn "reading file $file\n" if (defined $verbose);
    my ($name, $seq);
    open F, "$file" or die "cannot open $file\n";
    while (<F>) {
        chomp;
        if (/>/) {
            $name = $_;
        }
        else {
            $seq .= $_;
        }
    }
    close F;
    return $name, $seq;
}

sub printFasta {
    my ($head, $seq, $file) = @_;
    my $col = 70;
    warn "writing file $file\n" if (defined $verbose);
    open  F, ">$file" or die "cannot write $file\n";
    print F "$head\n";
    while ($seq) {
        my $s = substr($seq, 0, $col);
        print F "$s\n";
        substr($seq, 0, $col) = '';
    }
    close F;
}

sub checkIndex {
    my ($engine, $genome) = @_;
    if ($engine eq 'rmblast') {
        unless (-e "$genome.nhr" and -e "$genome.nin" and -e "$genome.nsq") {
            warn "missing indexes for $genome, generating them\n" if (defined $verbose);
            system ("$makeblastdb -in $genome -dbtype nucl");
        }
    }
    elsif ($engine eq 'wublast') {
        unless (-e "$genome.xnd" and -e "$genome.xns" and -e "$genome.xnt") {
            warn "missing indexes for $genome, generating them\n" if (defined $verbose);
            system ("$xdformat -n $genome");
        }
    }
    else {
        die "Engine $engine is not supported\n";
    }
}

sub loadGenome {
    my ($file) = @_;
    warn "reading file $file\n" if (defined $verbose);
    open F, "$file" or die "cannot open $file\n";
    my $name = '';
    while (<F>) {
        chomp;
        if (m/^>/) {
            s/>//;
            s/\s+.*//;
            $name = $_;
        }
        else {
            $genome{$name}     .= $_;
            $genome_len{$name} += length $_;
        }
    }
    close F;
}

sub extendRepeat {
    my ($rep)       = @_;
    my $temp        = $conf{'temp'};
    my $minlen      = $conf{'minlen'};
    my $minscore    = $conf{'minscore'};
    my $maxn        = $conf{'maxn'};
    my $maxe        = $conf{'evalue'};
    my $region      = $conf{'region'};
    my $hits;  
    
    open  F, ">$temp.fa" or die "cannot write $temp.fa\n";
    print F  ">repeat\n$rep\n";
    if  ($region =~ m/,/) {
        my ($rini, $rend) = split (/,/, $region);
        my $seed = substr ($rep, $rini - 1, $rend - $rini);
        print F ">seed\n$seed\n";
    }
    close F;
    open  O, ">$temp.out" or die "cannot write $temp.out\n";

    $Engine->setQuery("$temp.fa");
    $Engine->setSubject($genome);
    ($status, $searchResults) = $Engine->search();
    die "Search returned an error: $status\n" if ($status > 0);
    
    $hits = $searchResults->size();
    warn "Found $hits candidate hits\n" if (defined $verbose);
    for (my $i = 0 ; $i < $hits; $i++) {
        my $qName  = $searchResults->get( $i )->getQueryName;
        my $qStart = $searchResults->get( $i )->getQueryStart;
        my $qEnd   = $searchResults->get( $i )->getQueryEnd;
        my $hName  = $searchResults->get( $i )->getSubjName;
        my $hStart = $searchResults->get( $i )->getSubjStart;
        my $hEnd   = $searchResults->get( $i )->getSubjEnd;
        my $dir    = $searchResults->get( $i )->getOrientation;
        my $score  = $searchResults->get( $i )->getScore;
        my $evalue = 0; # RMBlast doesn't report evalue :(
        $evalue = $searchResults->get( $i )->getPValue if ($conf{'engine'} eq 'wublast');
        my $qLen   = $qEnd - $qStart;
        my $hLen   = $hEnd - $hStart;
        my $seq    = '';
        $dir = 'F' unless ($dir eq 'C');
        next if ($score  < $minscore);
        next if ($evalue > $maxe);
        next if ($hLen   < $minlen);
        $conf{'search_hits'}++;
        print O  join "\t", $qName, $qStart, $qEnd, $hName, $hStart, $hEnd, $dir, $evalue, "$score\n";
    }
    close O;
    
    system ("sort -rn -k 9 $temp.out > $temp.out.sort");
    system ("mv $temp.out.sort $temp.out");
    $conf{'search'} = 0;
    my $res = extendRepeatNoSearch($rep, 1);
    return "$res";
}

sub extendRepeatNoSearch {
    my ($rep, $iter) = @_;
    my @all_seqs    = ();
    my @left_seqs   = ();
    my @right_seqs  = ();
    my $left        = '';
    my $right       = '';
    my $cons        = '';
    my $base        = '';
    my $clip        = '';
    my $null        = '';
    my $temp        = $conf{'temp'};
    my $matrix      = $conf{'matrix'};
    my $minlen      = $conf{'minlen'};
    my $minscore    = $conf{'minscore'};
    my $minseq      = $conf{'minseq'};
    my $numseq      = $conf{'numseq'};
    my $maxn        = $conf{'maxn'};
    my $size        = $conf{'size'};
    my $win         = $conf{'win'};
    my $no3p        = $conf{'no3p'};
    my $no5p        = $conf{'no5p'};
    my $maxe        = $conf{'evalue'};
    my $ext         = 'Z' x $size;
    my $hits;
    my $ini;
    my $end;
    my $len;
    
    open  F, ">$temp.fa" or die "cannot write $temp.fa\n";
    print F  ">repeat\n$rep\n";
    close F;

    open S, "$temp.out" or die "cannot read $temp.out\n";
    while (<S>) {
        chomp;
        my ($qName, $qStart, $qEnd, $hName, $hStart, $hEnd, $dir, $evalue, $score) = split (/\t/, $_);
        my $qLen   = $qEnd - $qStart;
        my $hLen   = $hEnd - $hStart;
        my $seq    = '';
        next if ($score  < $minscore);
        next if ($evalue > $maxe);
        next if ($hLen   < $minlen);
        
        if ($no5p == 0 and $no3p == 0) {
            last if (($#left_seqs + $#right_seqs + 2) >= (2 * $numseq));
        }
        elsif ($no5p == 0) {
            last if (($#left_seqs + 1) >= $numseq);
        }
        elsif ($no3p == 0) {
            last if (($#right_seqs + 1) >= $numseq);
        }

        if ($no5p == 0) {
            if ($qStart <= $win and ($#left_seqs + 1) <= $numseq) {
                if ($dir eq 'C') {
                    $ini = $hStart - 1;
                    $ini = 0 if ($ini < 0);
                    $end = $hEnd + ($size * $iter) - 1;
                    $end = length $genome{$hName} if ($end > length $genome{$hName});
                    $len = $end - $ini;
                    $seq = revcomp(substr($genome{$hName}, $ini, $len));
                }
                else {
                    $ini = $hStart - ($size * $iter) - 1;
                    $ini = 0 if ($ini < 0);
                    $end = $hEnd - 1;
                    $end = length $genome{$hName} if ($end > length $genome{$hName});
                    $len = $end - $ini;
                    $seq = substr($genome{$hName}, $ini, $len);
                }
                if ($qName eq 'seed') {
                    push @left_seqs, ">lseed_$hName:$ini-$end:$dir\n$seq\n";
                } 
                else {
                    push @left_seqs, ">left_$hName:$ini-$end:$dir\n$seq\n";
                }
            }
        }
        
        if ($no3p == 0) {
            if ($qEnd > ($qLen - $win) and ($#right_seqs + 1) <= $numseq) {
                if ($dir eq 'C') {
                    $ini = $hStart - ($size * $iter) - 1;
                    $ini = 0 if ($ini < 0);
                    $end = $hEnd - 1;
                    $end = length $genome{$hName} if ($end > length $genome{$hName});
                    $len = $end - $ini;
                    $seq = revcomp(substr($genome{$hName}, $ini, $len));                    
                }
                else {
                    $ini = $hStart - 1;
                    $ini = 0 if ($ini < 0);
                    $end = $hEnd + ($size * $iter) - 1;
                    $end = length $genome{$hName} if ($end > length $genome{$hName});
                    $len = $end - $ini;
                    $seq = substr($genome{$hName}, $ini, $len);
                }
                if ($qName eq 'seed') {
                    push @right_seqs, ">rseed_$hName:$ini-$end:$dir\n$seq\n";
                } 
                else {
                    push @right_seqs, ">right_$hName:$ini-$end:$dir\n$seq\n";
                }
            }
        }
    }
    close S;
    
    my $nleft  = scalar @left_seqs;
    my $nright = scalar @right_seqs;
    
    warn "$nleft in left side, $nright in right side\n" if (defined $verbose); 
    
    push @all_seqs, @left_seqs;
    push @all_seqs, @right_seqs;
    my $ext_rep  = $rep;
    $ext_rep = "$ext$ext_rep" if (($#left_seqs  + 1)  >= $minseq);
    $ext_rep = "$ext_rep$ext" if (($#right_seqs + 1)  >= $minseq);
    ($cons, $base)  = createConsensus("$ext_rep", @all_seqs);
    
    if ($base  =~ m/^(Z+)/) {
        $clip  = $1;
        $left  = substr($cons, 0, length $clip);
        $null  = $left =~ tr/N/N/;
        if ($null >= $maxn) {
            substr($cons, 0, length $clip) = '';
            $conf{'no5p'} = 1;
        }
    }
    if ($base  =~ m/(Z+)$/) {
        $clip  = $1;
        $right = substr($cons, (length $cons) - (length $clip), length $clip);
        $null  = $right =~ tr/N/N/;
        if ($null >= $maxn) {
            substr($cons, (length $cons) - (length $clip), length $clip) = '';
            $conf{'no3p'} = 1;
        }
    }
    
    warn "extensions: left=$left, right=$right\n" if (defined $verbose);
    my $res = $cons;
    $res =~ s/^N+//;
    $res =~ s/N+$//;
    return "$res";
}

sub createConsensus {
    my $rep = shift @_;
    my $temp = $conf{'temp'};
    warn "creating consensus\n" if (defined $verbose);
    
    open  R, ">$temp.rep.fa" or die "cannot write $temp.rep.fa\n";
    print R  ">rep0\n$rep\n";
    close R;
    
    open  F, ">$temp.repseq.fa" or die "cannot write $temp.repseq.fa\n";
    while (my $seq = shift @_) {
        print F $seq;
    }
    close F;
    
    system "$cross_match $temp.repseq.fa $temp.rep.fa $cm_param -alignments > $temp.cm_out 2> /dev/null";
    
    system "$linup -i $temp.cm_out $matrix_dir/linup/nt/linupmatrix > $temp.ali 2> /dev/null";
    
    my $cons = '';
    my $base = '';
    open A, "$temp.ali" or die "cannot open file $temp.ali\n";
    while (<A>) {
        chomp;
        if (m/^consensus/) {
            s/consensus\s+\d+\s+//;
            s/\s+\d+$//;
            s/-//g;
            $cons .= $_;
        }
        elsif (m/^rep0/) {
            s/rep0\s+\d+\s+//;
            s/\s+\d+$//;
            s/-//g;
            $base .= $_;
        }
    }
    close A;
    
    return ($cons, $base);
}

sub readBlocks {
    my $file = shift;
    local $/ = "\n\n";
    open F, "$file" or die "cannot open $file\n";
    my @blocks = <F>;
    close F;
    return $blocks[0], $blocks[-1];
}

sub checkDiv {
    my ($div)    = @_;
    my $par      = '';
    my $minscore = $conf{'minscore'};
    my $minmatch = $conf{'minmatch'};
    if    ($div == 14) { $par = "-M $matrix_dir/crossmatch/14p41g.matrix -gap_init -33 -gap_ext -6 -minscore $minscore -minmatch $minmatch"; }
    elsif ($div == 18) { $par = "-M $matrix_dir/crossmatch/18p41g.matrix -gap_init -30 -gap_ext -6 -minscore $minscore -minmatch $minmatch"; }
    elsif ($div == 20) { $par = "-M $matrix_dir/crossmatch/20p41g.matrix -gap_init -28 -gap_ext -6 -minscore $minscore -minmatch $minmatch"; }
    elsif ($div == 25) { $par = "-M $matrix_dir/crossmatch/25p41g.matrix -gap_init -25 -gap_ext -5 -minscore $minscore -minmatch $minmatch"; }
    else  { die "Wrong divergence value, use [14,18,20,25]\n"; }
    
    warn "div=$div, cm_param=$par\n" if (defined $verbose);
    return $par;
}

sub revcomp{
    my ($s) = @_;
    my $r = reverse $s;
    $r =~ tr/ACGTacgt/TGCAtgca/;
    return $r;
}
