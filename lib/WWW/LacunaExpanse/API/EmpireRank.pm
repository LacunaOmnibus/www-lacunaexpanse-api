package WWW::LacunaExpanse::API::EmpireRank;

use Moose;
use Carp;

# Private attributes
has 'sort_by'           => (is => 'ro', default => 'empire_size_rank');
has 'page_number'       => (is => 'rw', default => 1);
has 'connection'        => (is => 'ro', lazy_build => 1);
has 'index'             => (is => 'rw', default => 0);
has 'cached'            => (is => 'ro', default => 0);

my $path = '/stats';

my @simple_strings  = qw(total_empires);
my @date_strings    = qw();
my @other_strings   = qw(empire_stats);

for my $attr (@simple_strings, @date_strings, @other_strings) {
    has $attr => (is => 'ro', writer => "_$attr", lazy_build => 1);

    __PACKAGE__->meta()->add_method(
        "_build_$attr" => sub {
            my ($self) = @_;
            $self->update;
            return $self->$attr;
        }
    );
}

sub _build_connection {
    return WWW::LacunaExpanse::API::Connection->instance;
}

# Reset to the first record
#
sub first {
    my ($self) = @_;

    $self->index(0);
    return $self->next;
}

## Reset to the last record
##
#sub last {
#    my ($self) = @_;
#
#    $self->index($self->total_empires - 1);
#    return $self->next;
#}
#
## Return the previous Empire in the Rank List
##
#sub previous {
#    my ($self) = @_;
#
#    if ($self->index <= 0) {
#        return;
#    }
#
#    my $page_number = int($self->index / 25) + 1;
#    if ($page_number != $self->page_number) {
#        $self->page_number($page_number);
#        $self->update;
#    }
#    my $empire_stat = $self->empire_stats->[$self->index % 25];
#    $self->index($self->index - 1);
#    return $empire_stat;
#}

# Return the next Empire in the Rank List
#
sub next {
    my ($self) = @_;

    if ($self->index >= $self->total_empires) {
        return;
    }

    my $page_number = int($self->index / 25) + 1;
    if ($page_number != $self->page_number) {
        $self->page_number($page_number);
        $self->update;
    }
    my $empire_stat = $self->empire_stats->[$self->index % 25];
    $self->index($self->index + 1);
    return $empire_stat;
}

# Return the total number of empires
#
sub count {
    my ($self) = @_;

    return $self->total_empires;
}


# Refresh the object from the Server
#
sub update {
    my ($self) = @_;

#     $self->connection->debug(1);
    my $result = $self->connection->call($path, 'empire_rank',[
        $self->connection->session_id, $self->sort_by, $self->page_number]);

    $self->connection->debug(0);

    $result = $result->{result};

    # simple strings
    for my $attr (@simple_strings) {
        my $method = "_$attr";
        $self->$method($result->{$attr});
    }

    # date strings
    for my $attr (@date_strings) {
        my $date = $result->{$attr};
        my $method = "_$attr";
        $self->$method(WWW::LacunaExpanse::API::DateTime->from_lacuna_string($date));
    }

    # other strings
    my @empire_stats;
    for my $empire_hash (@{$result->{empires}}) {
        my $empire = WWW::LacunaExpanse::API::Empire->new({
            id      => $empire_hash->{empire_id},
            name    => $empire_hash->{empire_name},
        });
        my $alliance = WWW::LacunaExpanse::API::Alliance->new({
            id      => $empire_hash->{alliance_id},
            name    => $empire_hash->{alliance_name},
        });

        my $empire_stat = WWW::LacunaExpanse::API::EmpireStats->new({
            empire                  => $empire,
            alliance                => $alliance,
            colony_count            => $empire_hash->{colony_count},
            population              => $empire_hash->{population},
            empire_size             => $empire_hash->{empire_size},
            building_count          => $empire_hash->{building_count},
            average_building_level  => $empire_hash->{average_building_level},
            offense_success_rate    => $empire_hash->{offense_success_rate},
            defense_success_rate    => $empire_hash->{defense_success_rate},
            dirtiest                => $empire_hash->{dirtiest},
        });

        push @empire_stats, $empire_stat;
    }
    $self->_empire_stats(\@empire_stats);
}

sub total_pages {
    my ($self) = @_;

    return int($self->total_empires / 25);
}

;
1;
