// functions.js
// part of modENCODE faceted search infrastructure
// Author: Lincoln D. Stein <lincoln.stein@gmail.com>
// (c) 2011 Ontario Institute for Cancer Research
// License: Perl Artistic License 2.0; allows for redistribution with citation of original author

var SelectedItems = new Hash();
var GlobalTimeout = new Hash();
var balloon       = new Balloon;
BalloonConfig(balloon,'GBubble');
balloon.images    = 'GBubble';
balloon.delayTime = 500;

function clear_all () {
    SelectedItems = new Hash();
    hilight_items();
    $('selection_count').innerHTML   = 'No tracks selected';
    $('dataset_count').innerHTML     = 'Selected Datasets:';
    refresh_shopping_cart();
}

function get_id (container) {
    return container.getAttribute('ex:itemid');
}

function popup (event, container) {
    var html = container.select('div.popup');
    balloon.showTooltip(event,html[0].innerHTML);
}

function toggle_track (checkbox,turn_on) {
    var container = checkbox.ancestors().find(
	function(el) { return el.hasClassName('submission')});
    var id = get_id(container);

    if (turn_on == null)
	turn_on = !container.hasClassName('selected');

    if (turn_on) {
	container.addClassName('selected');
	SelectedItems.set(id,1);
    } else {
	container.removeClassName('selected');
	SelectedItems.unset(id);
    }
    checkbox.checked = turn_on;
    
    var selected = SelectedItems.keys();
    if (selected.size() > 0) {
	var url     = format_url();
	var sources = url.keys();
	$('dataset_count').innerHTML     = selected.size()+' Selected Datasets:';
	$('selection_count').innerHTML   = selected.size()+' datasets selected';
	$('selection_count').innerHTML  += ' [<a href="javascript:clear_all()">clear</a>].';
	$('selection_count').innerHTML  += '<br/>Browse ';
	if (url.keys().size() > 0) {
	    url.keys().each(function (e) { 
		var u = url.get(e);
		$('selection_count').innerHTML += '<a target="_new" href="' + u + '">'+e+' tracks</a> ';
	    });
	} else {
	    $('selection_count').innerHTML += '<i>invalid track</i>';
	}
	$('selection_count').innerHTML += '.<br/><a href="foobar">Download</a> selected data.';
    } else {
	$('dataset_count').innerHTML     = 'Selected Datasets:';
	$('selection_count').innerHTML='No tracks selected';
    }
    refresh_shopping_cart();
}

function refresh_shopping_cart () {
    var cart = $('shopping_cart');
    if (cart == null) return;
    cart.innerHTML = '';
    var selected = SelectedItems.keys().sort();
    if (selected.size() == 0) cart.innerHTML = '<i style="color:gray">No datasets selected</i>';
    selected.each(function (e) {
	var id               = 'check_'+e;
	var remove           = '<input type="checkbox" checked="on" id="'+id+'" onchange="trash(this)"/>';
//	cart.insert('<li>'+remove+'<label for="'+id+'">'+e+'</label></li>');
	cart.insert('<li>'+remove+'<span>'+e+'</span>'+'</li>');
    });
}

function hilight_items () {
    var divs = $$('.submission');
    divs.each (function (d) {
        var id = d.getAttribute('ex:itemid');
        if (SelectedItems.get(id)) {
            d.addClassName('selected');
            d.select('input')[0].checked=1;
        } else {
            d.removeClassName('selected');
            d.select('input')[0].checked=0;
        }
    });
}

function trash (checkbox) {
    var us    = checkbox.id.indexOf('_');
    var id    = checkbox.id.substr(us+1);
    var label = checkbox.nextSiblings()[0];
    if (!checkbox.checked) {
	label.addClassName('strikeout');
	var t = window.setTimeout(function () {
	    toggle_track($(id),false);
	    GlobalTimeout.unset(id);
	},2000);
	GlobalTimeout.set(id,t);
    } else {
	label.removeClassName('strikeout');
	var t = GlobalTimeout.get(id);
	if (t) {
	    window.clearTimeout(t);
	    GlobalTimeout.unset(id);
	}
    }
}

function format_url() {
    var selected = $$('.selected.submission');

    // consolidate sources, tracks and subtracks
    var tra    = new Hash();
    for (var i=0;i<selected.size();i++) {
	var tracks = window.database.getObjects(selected[i].getAttribute('ex:itemid'),'Tracks').toArray();
	tracks.each(function (e) {
	    var fields = e.split('/');
	    var source    = fields[0];
            var track     = fields[1];
            var subtrack  = fields[2];
	    if (subtrack == null) subtrack = '';
	    if (tra.get(source) == null )            tra.set(source,new Hash());
	    if (tra.get(source).get(track) == null)  tra.get(source).set(track, new Hash());
	    tra.get(source).get(track).set(subtrack,1);
        });
    }
    var url = new Hash();
    tra.keys().each(function (s) {
	var source = s;
	var tracks = tra.get(s);
	if (url.get(source)==null)
	    url.set(source,'http://modencode.oicr.on.ca/fgb2/gbrowse/'+source+'/?l=Genes');
	var v = url.get(source);
	tracks.keys().each(function (t) {
	    var subtracks = tracks.get(t).keys();
            v += ";l="+t;
	    if (subtracks[0] != '')
		v += '/' + subtracks.join('+');
	});
	url.set(source,v);
    });
    return url;
}
