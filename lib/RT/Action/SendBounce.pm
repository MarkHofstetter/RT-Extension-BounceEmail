# BEGIN BPS TAGGED BLOCK {{{
#
# COPYRIGHT:
#
# This software is Copyright (c) 1996-2015 Best Practical Solutions, LLC
#                                          <sales@bestpractical.com>
#
# (Except where explicitly superseded by other copyright notices)
#
#
# LICENSE:
#
# This work is made available to you under the terms of Version 2 of
# the GNU General Public License. A copy of that license should have
# been provided with this software, but in any event can be snarfed
# from www.gnu.org.
#
# This work is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301 or visit their web page on the internet at
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.html.
#
#
# CONTRIBUTION SUBMISSION POLICY:
#
# (The following paragraph is not intended to limit the rights granted
# to you to modify and distribute this software under the terms of
# the GNU General Public License and is only of importance to you if
# you choose to contribute your changes and enhancements to the
# community by submitting them to Best Practical Solutions, LLC.)
#
# By intentionally submitting any modifications, corrections or
# derivatives to this work, or any other work intended for use with
# Request Tracker, to Best Practical Solutions, LLC, you confirm that
# you are the copyright holder for those contributions and you grant
# Best Practical Solutions,  LLC a nonexclusive, worldwide, irrevocable,
# royalty-free, perpetual, license to use, copy, create derivative
# works based on those contributions, and sublicense and distribute
# those contributions and any derivatives thereof.
#
# END BPS TAGGED BLOCK }}}

#
package RT::Action::SendBounce;

use strict;
use warnings;

use base qw(RT::Action::SendEmail);

use Email::Address;

=head2 Prepare

=cut

sub Prepare {
    my $self = shift;

    my $txn = $self->TransactionObj;

    my $forwarded_txn = RT::Transaction->new( $self->CurrentUser );
    $forwarded_txn->Load( $txn->Field );
    return 0 unless $forwarded_txn->id;

    $self->{ForwardedTransactionObj} = $forwarded_txn;

    my $entity = ContentSansFromAsMIME($self->ForwardedTransactionObj->Attachments->First, Children => 1);

    my $txn_attachment = $self->TransactionObj->Attachments->First;
    for my $header (qw/To Cc Bcc/) {
#        if ( my $original = $entity->head->get( $header ) ) {
#            $entity->head->add( "X-Original-$header" => Encode::encode( "UTF-8", $original ) );
#        }

        if ( my $v = $txn_attachment->GetHeader( $header ) ) {
            $entity->head->replace( "Resent-$header" => Encode::encode( "UTF-8", $v ) );
        } else {
            $entity->head->delete( $header );
        }
    }

    # RFC5322, section 3.3.6
    require RT::Date;
    my $date = RT::Date->new( $txn->CurrentUser );
    $date->SetToNow;
    $entity->head->add('Resent-Date', $date->RFC2822(Timezone => 'server') );
    $entity->head->add('Resent-From' => RT->Config->Get('CorrespondAddress'));
    $entity->head->add( Bcc => 'discard@univie.ac.at' )
        unless grep($entity->head->get($_) && length($entity->head->get($_)),
                    @RT::Action::SendEmail::EMAIL_RECIPIENT_HEADERS);

    if ( RT->Config->Get('ForwardFromUser') ) {
        $entity->head->replace( 'X-RT-Sign' => 0 );
    }

    $self->TemplateObj->{MIMEObj} = $entity;


#    $self->SUPER::Prepare();
#    SUPER::Prepare destroys Content-Type of Attachments.
#    Do some needed stuff ourselfs here
#    copied from RT::Action::SendEmail
    # Header
    $self->SetRTSpecialHeaders();

    my %seen;
    foreach my $type (@RT::Action::SendEmail::EMAIL_RECIPIENT_HEADERS) {
        @{ $self->{$type} }
            = grep defined && length && !$seen{ lc $_ }++,
            @{ $self->{$type} };
    }

    $self->RemoveInappropriateRecipients();
    return 1;
}

# This is a copy of RT::Attachment::ContentAsMIME, which
# copies all headers except the "From " and X-RT-* headers.
sub ContentSansFromAsMIME {
    my ($self) = shift;
    my %opts = (
        Children => 0,
        @_
    );

    my $entity = MIME::Entity->new();
    foreach my $header ($self->SplitHeaders) {
        next if $header =~ m/^From / || $header =~ m/^X-RT-/;
        my ($h_key, $h_val) = split /:/, $header, 2;
        $entity->head->add(
            $h_key, $self->_EncodeHeaderToMIME($h_key, $h_val)
        );
    }

    if ($entity->is_multipart) {
        if ($opts{'Children'} and not $self->IsMessageContentType) {
            my $children = $self->Children;
            while (my $child = $children->Next) {
                $entity->add_part( $child->ContentAsMIME(%opts) );
            }
        }
    } else {
        # since we want to return original content, let's use original encoding
        $entity->head->mime_attr(
            "Content-Type.charset" => $self->OriginalEncoding )
          if $self->OriginalEncoding;

        $entity->bodyhandle(
            MIME::Body::Scalar->new( $self->OriginalContent )
        );
    }

    return $entity;
}

sub SetSubjectToken {
    my $self = shift;
    return if RT->Config->Get('ForwardFromUser');
    $self->SUPER::SetSubjectToken(@_);
}

sub ForwardedTransactionObj {
    my $self = shift;
    return $self->{'ForwardedTransactionObj'};
}

sub SetReturnAddress {
}

RT::Base->_ImportOverlays();

1;
