// functions.js
// part of modENCODE faceted search infrastructure
// Author: Lincoln D. Stein <lincoln.stein@gmail.com>
// (c) 2011 Ontario Institute for Cancer Research
// License: Perl Artistic License 2.0; allows for redistribution with citation of original author

var SelectedItems = new Hash();
var GlobalTimeout = new Hash();
var Popups        = new Hash();
var rowIndex   = 0;
var balloon       = new Balloon;
BalloonConfig(balloon,'GBubble');
balloon.images    = 'GBubble';
balloon.delayTime = 500;

function clear_all () {
    SelectedItems = new Hash();
    hilight_items();
    $('dataset_count').innerHTML     = 'Selected Datasets:';
    $('retrieve_buttons').hide();
    shopping_cart_clear();
}

function get_id (container) {
    return container.getAttribute('ex:itemid');
}

function popup (event, container) {
    var html = Element.select(container.parentNode,'div.popup');
    balloon.showTooltip(event,html[0].innerHTML);
}

function find_container (checkbox) {
    Element.extend(checkbox);
    var container = checkbox.ancestors().find(
	function(el) { return el.hasClassName('submission')});
    return container;
}

function toggle_track (checkbox,turn_on) {
    var container = find_container(checkbox);
    var id        = checkbox.id;
    if (turn_on == null)
	turn_on = !container.hasClassName('selected');
    toggle_dataset(id,turn_on);
}

function toggle_dataset (id,turn_on) {
    if (turn_on) {
	SelectedItems.set(id,1);
	shopping_cart_add(id);
    } else {
	SelectedItems.unset(id);
	shopping_cart_remove(id);
    }
    var checkbox = $(id);
    if (checkbox != null) {
	checkbox.checked = turn_on;
	var container    = find_container(checkbox);
	hilite_row(container,turn_on);
    }
    shopping_cart_check();
}

function shopping_cart_clear () { 
    var cart = $('shopping_cart');
    if (cart == null) return;
    cart.innerHTML = '';
    Popups = new Hash();  // clear it
    shopping_cart_check();
}

function shopping_cart_check () {
    var element = $('shopping_cart');
    var urls;
    if (element.select('li').size() == 0) {
	element.innerHTML = '<i style="color:gray">No datasets selected</i>';
	$('retrieve_buttons').innerHTML = '';
	$('retrieve_buttons').hide();
    } else {
	var selected = SelectedItems.keys();
	$('dataset_count').innerHTML     = selected.size()+' Selected Datasets:';
	var buttons = $('retrieve_buttons');
	buttons.innerHTML = '';
	urls        = format_url();
	var sources = urls.keys();
	urls.keys().each(function (e) {
	    var u = urls.get(e);
	    var window_name = 'browse_'+e;
	    buttons.insert(new Element('button',
				       {id:window_name}).update('Browse '+e.ucfirst()+' Tracks'));
	});
	var accessions = selected.map(function (l) {
	    return window.database.getObjects(l,'submission').toArray();
	});
	var url = 'http://www.foo.org/cgi-bin/me_download?download='+accessions.join('+');
	buttons.insert(new Element('button',{id:'download'}).update('Download Datasets'));
	buttons.insert(new Element('button',{id:"clear_all"}).update('Clear All'));

	$('clear_all').onclick = function() {clear_all()};
	$('download').onclick  = function() {alert(url)};
	urls.keys().each(function (e) {
	    var u = urls.get(e);
	    var window_name = 'browse_'+e;
	    $(window_name).onclick = function () {window.open(u,window_name)};
	});
	$('retrieve_buttons').show();
    }
}

function shopping_cart_add (dataset) {
    var cart = $('shopping_cart');
    if (cart == null) return;
    var item_id = 'cart_'+dataset;
    if ($(item_id) != null) 
	return; // already there
    if (cart.select('li').size() == 0)
	cart.innerHTML = '';

    // popup balloon data needs to be cached
    var container              = find_container($(dataset));
    var handler;
    try {
	var popup_html  = container.select('div.popup')[0].innerHTML;
	Popups.set(dataset,popup_html);
	handler = 'balloon.showTooltip(window.event,Popups.get(\''+dataset.gsub("'","\\'")+'\'))';
    } catch (e) {
	try {
	    var popup_html = build_popup(dataset);
	    Popups.set(dataset,popup_html);
	    handler = 'balloon.showTooltip(window.event,Popups.get(\''+dataset.gsub("'","\\'")+'\'))';	    
	} catch (e) {
	    handler = null;
	}
    }

    var remove           = new Element('input',{type:'checkbox',
						checked:true,
						id: 'check_'+dataset,
						onchange: 'trash(this)'
					       });
    var span = new Element('span',{style      :'cursor:pointer',
				   onmouseover: handler
				  }).update(dataset);
    var org  = window.database.getObjects(dataset,'organism').toArray().join(',');
    span.insert(' (<i>'+org+'</i>)');
    var li   = new Element('li',{id:item_id});
    li.insert(remove).insert(span);
    cart.insert({top:li});

    //IE workarounds
    if (Prototype.Browser.IE) {
	remove.checked  = true;
	remove.id       = 'check_'+dataset;
	remove.onclick  = function () {trash(remove)};
	span.onmouseover = function() {balloon.showTooltip(window.event,popup_html)}
    }
}

function shopping_cart_remove (dataset) {
    var item_id = 'cart_'+dataset;
    var element = $(item_id);
    if (element==null) return;
    element.remove();
    Popups.unset(dataset);
    shopping_cart_check();
}

function hilight_items () {
    var divs = $$('.submission');
    if (divs == null) return;
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
	    toggle_dataset(id,false);
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

function build_popup (label) {
    var html   = '';
    var fields = new Array('organism','experiment','technique','target','factor',
			   'Developmental-Stage','Cell-Line','Tissue','temperature','Compound');
    fields.each(function (a) {
	var value = window.database.getObjects(label,a).toArray()[0];
	if (value != null) {
	    html += '<div>';
            html += '<span class="field-label">'+a.ucfirst()+':</span> ';
	    html += '<span class="field-value">'+value+'</span>';
	    html += '</div>';
	}
     });
    return html;
}

function format_url() {
    var selected = SelectedItems.keys();

    // consolidate sources, tracks and subtracks
    var tra    = new Hash();
    for (var i=0;i<selected.size();i++) {
	var tracks = window.database.getObjects(selected[i],'Tracks').toArray();
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

String.prototype.ucfirst = function () {

    // Split the string into words if string contains multiple words.
    var x = this.split(/\s+/g);

    for (var i = 0; i < x.length; i++) {

        // Splits the word into two parts. One part being the first letter,
        // second being the rest of the word.
        var parts = x[i].match(/(\w)(.*)/);

        // Put it back together but uppercase the first letter and
        // lowercase the rest of the word.
        x[i] = parts[1].toUpperCase() + parts[2].toLowerCase();
    }

    // Rejoin the string and return.
    return x.join(' ');
};

function zebraStyler (item, database, tr, index) {
    var tr=tr.rows[index+1];
    hilite_row(tr,SelectedItems.get(item),item);
}

function hilite_row (row,turn_on) {
    row.removeClassName('odd');
    row.removeClassName('even');

    if (turn_on) {
	var cb = row.select('input')[0];
	cb.checked = true;
    }

    if (turn_on) {
	row.addClassName('selected') 
    } else {
	row.removeClassName('selected');
	row.addClassName(row.rowIndex %2 ? 'odd' : 'even');
    }
}