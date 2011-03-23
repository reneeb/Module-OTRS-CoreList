#!/usr/bin/perl

use strict;
use warnings;

use Archive::Tar;
use Clone qw(clone);
use Data::Dumper;
use File::Spec;
use File::Temp;
use Net::FTP;

my $ftp_host  = 'ftp.otrs.org';
my $local_dir = File::Temp::tempdir();
my @dirs      = qw(pub otrs);

my $ftp = Net::FTP->new( $ftp_host, Debug => 0 );
$ftp->login();

for my $dir ( @dirs ) {
    $ftp->cwd( $dir );
}

my @files   = $ftp->ls;
my @tar_gz  = grep{ m{ \.tar\.gz \z }xms }@files;
my @no_beta = grep{ !m{ -beta }xms }@tar_gz;

my %global;
my %hash;

my $flag = 0;

FILE:
for my $file ( @no_beta ) {
    my ($major,$minor,$patch) = $file =~ m{ \A otrs - (\d+) \. (\d+) \. (\d+) }xms;
    
    next FILE if !(defined $major and defined $minor);
    
    next FILE if $major < 2;
    next FILE if $major == 2 and $minor < 3;
    
    print STDERR "Try to get $file\n";
    
    my $local_path = File::Spec->catfile( $local_dir, $file );
    
    $ftp->binary;
    $ftp->get( $file, $local_path );
    
    my $tar              = Archive::Tar->new( $local_path, 1 );
    my @files_in_archive = $tar->list_files;
    my @modules          = grep{ m{ \.pm \z }xms }@files_in_archive;
    
    my $version = '';
    
    MODULE:
    for my $module ( @modules ) {
        next MODULE if $module =~ m{/scripts/};
    
        my ($otrs,$modfile) = $module =~ m{ \A otrs-(\d+\.\d+\.\d+)/(.*) }xms;
        my $is_cpan = $modfile =~ m{cpan-lib}xms;
        
        my $key = $is_cpan ? 'cpan' : 'core';
        
        (my $modulename = $modfile) =~ s{/}{::}g;
        $modulename =~ s{\.pm}{}g;
        $modulename =~ s{Kernel::cpan-lib::}{}g if $is_cpan;
        
        $version = $otrs;
        
        $hash{$otrs}->{$key}->{$modulename} = 1;
    }
    
    if ( !$flag ) {
        %global = %{ clone( $hash{$version} ) };
    }
    else {
        for my $type ( keys %{ $hash{$version} } ) {
            for my $modulename ( keys %{ $hash{$version}->{$type} } ) {
                $global{$type}->{$modulename}++;
            }
        }
    }
    
    $flag++;
}

$flag--;

# check if modules could stay in global hash
my @to_delete;
for my $type ( keys %global ) {
    for my $modulename ( keys %{ $global{$type} } ) {
        if ( $global{$type}->{$modulename} < $flag ) {
            delete $global{$type}->{$modulename};
        }
        else {
            push @to_delete, $modulename;
        }
    }
}

# delete modules that are stored in global hash
for my $otrs_version ( keys %hash ) {
    for my $type ( keys %{ $hash{$otrs_version} } ) {
        delete @{ $hash{$otrs_version}->{$type} }{@to_delete};
    }
}

$Data::Dumper::Sortkeys = 1;

if ( open my $fh, '>', 'corelist' ) {
    print $fh Dumper \%global;
    print $fh "\n";
    print $fh Dumper \%hash;
}
