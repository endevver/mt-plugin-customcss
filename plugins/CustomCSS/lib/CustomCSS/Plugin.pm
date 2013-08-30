# Copyright (C) 2009 Byrne Reese

package CustomCSS::Plugin;

use strict;
use warnings;

# Check to see if this theme has custom CSS enabled. If so, show the Customize
# Stylesheet option in the Design menu.
sub uses_custom_css {
    my $app  = MT->instance;
    my $blog = $app->blog;

    # Don't show at the system level.
    return 0 if !$blog;

    # If the user has forcibly enabled custom css, then return true.
    return 1 if $app->component('customcss')->get_config_value(
        'force_enable_custom_css',
        'blog:' . $blog->id
    );

    # Grab the templates for the template set used for this blog.
    my $ts = $app->blog->template_set;
    my $tmpl_hash = $app->registry('template_sets',$ts,'templates');
    if (ref($tmpl_hash) eq 'ARRAY' && $tmpl_hash->[0] eq '*') {
        $tmpl_hash = $app->registry("default_templates");
    }

    # If a bunch of templates couldn't be found, we don't want to display the
    # menu option.
    return 0 if (ref($tmpl_hash) ne 'HASH');

    # If the user is utilizing a template set for which custom css has been
    # enabled for an index template, return true.
    my $tmpls = $tmpl_hash->{'index'};
    foreach my $t (keys %$tmpls) {
        return 1 if $tmpls->{$t}->{'custom_css'};
    }

    return 0;
}

sub edit {
    my $app     = shift;
    my ($param) = @_;
    my $q       = $app->can('query') ? $app->query : $app->param;

    # Custom CSS works at the blog level only, so if the user is clicking over
    # to the system level, just redirect to the blog dashboard.
    if ( !$app->blog ) {
        $app->redirect(
            $app->uri(
                'mode' => 'dashboard',
            )
        );
    }

    $param ||= {};

    # to trigger autosave logic in main edit routine
    $param->{autosave_support} = 1;

    my $blog        = $app->blog;
    my $cfg         = $app->config;
    my $perms       = $app->permissions;
    my $can_preview = 0;

    # The search_label and object_type parameters are used to help populate the
    # Search box.
    $param->{search_label} = $app->translate('Templates');
    $param->{object_type}  = 'template';
    $param->{saved}        = 1 if $q->param('saved');
    $param->{screen_id}    = "edit-template-stylesheet";

    my $scope = "blog:" . $blog->id;
    $param->{'text'}
        = $app->component('customcss')->get_config_value('custom_css',$scope);

    $param->{template_lang} = 'css';

    # Populate structure for template snippets; only displayed in MT4.
    if ( my $snippets = $app->registry('template_snippets') || {} ) {
        my @snippets;
        for my $snip_id ( keys %$snippets ) {
            my $label = $snippets->{$snip_id}{label};
            $label = $label->() if ref($label) eq 'CODE';
            push @snippets,
              {
                id      => $snip_id,
                trigger => $snippets->{$snip_id}{trigger},
                label   => $label,
                content => $snippets->{$snip_id}{content},
              };
        }
        @snippets = sort { $a->{label} cmp $b->{label} } @snippets;
        $param->{template_snippets} = \@snippets;
    }

    my $tmpl_name = 'custom_css.tmpl';
    $tmpl_name = 'custom_css_mt4.tmpl'
        if $app->product_version =~ /^4/;

    return $app->load_tmpl( $tmpl_name, $param );
}

sub save {
    my $app  = shift;
    my $q    = $app->can('query') ? $app->query : $app->param;
    my $blog = MT::Blog->load($q->param('blog_id'));

    my $css = $q->param('text');

    my $scope = "blog:" . $blog->id;
    $app->component('customcss')->set_config_value('custom_css',$css,$scope);

    my $ts = $app->instance->blog->template_set;
    my $tmpl_hash = $app->registry('template_sets',$ts,'templates');
    if (ref $tmpl_hash eq 'ARRAY' && $tmpl_hash->[0] eq '*') {
        $tmpl_hash = $app->registry("default_templates");
    }
    #use Data::Dumper;
    #MT->log( Dumper($tmpl_hash) );
    my $tmpls = $tmpl_hash->{'index'};
    foreach my $t (keys %$tmpls) {
        if ($tmpls->{$t}->{custom_css}) {
            my $tmpl = $app->model('template')->load({
                blog_id => $blog->id,
                identifier => $t,
            });
            $app->log({
                blog_id   => $blog->id,
                message   => 'Custom CSS plugn is republishing ' . $tmpl->name,
                author_id => $app->user->id,
                level     => $app->model('log')->INFO(),
                class     => "publish",
                category  => 'rebuild',
            });
            $app->rebuild_indexes(
                Blog     => $blog,
                Template => $tmpl,
                Force    => 1,
            );
        }
    }
    $app->add_return_arg( saved => 1 );
    return $app->call_return;
}

1;
__END__
