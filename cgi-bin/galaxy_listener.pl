#!/usr/bin/perl
# Galaxy Script Thing
# Kar Ming Chu
# July 2012

# Modified: /modencode/htdocs/js/exhibit/ajax/simile-ajax-bundle.js
# for compatibility with this script.

use strict;
use warnings;
use CGI qw(:standard);

my $galaxy_url = param("GALAXY_URL") || "";
my $tool_id = param("tool_id") || "";
# faceted browser URL
#my $url = "http://ec2-50-16-11-248.compute-1.amazonaws.com";
my $url = `ec2metadata | grep public-hostname | awk '{ print \$2 }'`;
chomp($url);
$url = "http://" . $url ;

my $js = "/js";

# content type; informs whatever calls this script of what it gets
print header('text/html');

print <<END;

<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html>
 <head>
    <title>Faceted Search of modENCODE Data Sets</title>
  
    <link href="/modencode.js" type="application/json" rel="exhibit/data" />

    <link rel='stylesheet' href="/css/common.css" type='text/css' />
    <link rel='stylesheet' href="/css/me.css" type='text/css' />

    <script src="$js/exhibit/ajax/simile-ajax-api.js"
            type="text/javascript"></script>

    <script src="$js/exhibit/exhibit-api.js"
            type="text/javascript"></script>

    <script src="$js/prototype.js"
            type="text/javascript"></script>

    <script src="$js/scriptaculous/scriptaculous.js"
	    type="text/javascript"></script>

    <script type="text/javascript" src="$js/balloon.config.js"></script>
    <script type="text/javascript" src="$js/balloon.js"></script>

    <script src="$js/galaxy_functions.js"
	    type="text/javascript">
    </script>

    <script type="text/javascript">
      var _gaq = _gaq || [];
      _gaq.push(['_setAccount', 'UA-25200492-2']);
      _gaq.push(['_trackPageview']);

      (function() {
      var ga = document.createElement('script'); ga.type = 'text/javascript'; ga.async = true;
      ga.src = ('https:' == document.location.protocol ? 'https://ssl' : 'http://www') + '.google-analytics.com/ga.js';
      var s = document.getElementsByTagName('script')[0]; s.parentNode.insertBefore(ga, s);
      })();
    </script>

</head> 

<body>
<div class="header">
    <h1><a href="http://www.modencode.org"><img src="http://www.modencode.org/static/img/logo.png" height="60" align="middle" border="0"/></a>
      Search modENCODE Data Sets</h1>
</div>

<!-- this is the search box, list of selected tracks, and control buttons -->
<div class="status">
  <table width="100%" border='0'>
    <tr>
      <td width="25%"></td>
      <th id="dataset_count">Selected Datasets:</th>
    </tr>
    <tr>
      <td class="notice">
	<span>Internet Explorer users: If this page is too slow for you, consider Firefox, Safari or Chrome. Please do not abort script execution.</span>
      </td>
      <td align="left">
	<ul id="shopping_cart"><i style="color:gray">No datasets selected</i></ul>
      </td>
    </tr>
    <tr>
      <td><b>Search:</b> <span id="searchbox" ex:role="facet" ex:facetClass="TextSearch"></span></td>
      <th>
	<!--Hide buttons that don't have to do with Galaxy-->
	<div id="retrieve_buttons">
	  <button id="browse_worm" disabled="1">Browse Worm Tracks</button>
	  <button id="browse_fly" disabled="1">Browse Fly Tracks</button>
	  <button id="modmine" disabled="1">View in ModMine</button>
	  <button id="download" disabled="1">Download</button>
	  <button id="urls" disabled="1">List Download URLs</button>
	  <button id="cloud" disabled="1">List Cloud Files</button>
	  <button id="clear_all" disabled="1">Clear All</button>
END

# if galaxy_url exists include galaxy button
if ($galaxy_url)
{
print <<END;
	  <!--Galaxy Stuff-->
	  <form id="galaxyForm" action="$galaxy_url" method="post">
      <input id="tool_id" name="tool_id" type="hidden" value="$tool_id"/>
      <input id="URL" name="URL" type="hidden" value="$url"/>

     <!-- <input id="galaxyInput" name="galaxyInput" type="hidden"/>-->
	  <!--Define galaxyStuff value on fly via javascript-->
		<button id="send_data_to_galaxy" type="button" disabled="1" style="width:150px;height:50px">Send to Galaxy</button>
	  </form>
END
}

print <<END;

	</div>
      </th>
    </tr>
  </table>
</div>

<!-- this is the faceted search area and results-->
<table border='0'>

<!-- left column, organism, technique, target and factor facets -->
  <!-- qtrinh added style="display:none" -->
  <td id="left-column" style="display:none" width="25%">
    <div class="notice">Search Filters</div>
    <div ex:role="facet" ex:collapsible="true" ex:facetLabel="Organism" ex:expression=".organism"  
	 ex:scroll="true" ex:sortMode="count" ex:height="5em"></div>
  <!-- qtrinh changed ex:collapsed= to false  -->
    <div ex:role="facet" ex:collapsible="true" ex:collapsed="false" ex:facetLabel="Project Category" 
	 ex:expression=".category"  ex:scroll="true" ex:sortMode="value" ex:height="13em"
	 ex:fixedOrder="Gene Structure;RNA expression profiling;TF binding sites;Other chromatin binding sites;Chromatin structure;Histone modification and replacement;Copy Number Variation;Replication;Metadata only">
    </div>
    <div  ex:role="facet" ex:collapsible="true" ex:collapsed="true" ex:facetLabel="Genomic Target Element" ex:expression=".target"    ex:scroll="true" ex:facetLabel="" ex:sortMode="count"></div>
    <div  ex:role="facet" ex:collapsible="true" ex:selection="ChIP-seq" ex:collapsed="false" ex:facetLabel="Technique" ex:expression=".technique" ex:scroll="true" ex:sortMode="count"></div>

    <div ex:role="facet" ex:collapsible="true" ex:collapsed="true" ex:facetLabel="Principal Investigator" ex:expression=".principal_investigator"  ex:scroll="true"></div>
    <div  ex:role="facet"  ex:collapsible="true" ex:collapsed="true" ex:facetLabel="Assay Factor" ex:expression=".factor"  ex:height:"200px"  ex:scroll="true" ex:facetLabel=""></div>
    <div  ex:role="facet"  ex:collapsible="true" ex:collapsed="true" ex:facetLabel="Developmental Stage" ex:expression=".Developmental-Stage" ex:scroll="true" ex:facetLabel=""></div>
    <div  ex:role="facet"  ex:collapsible="true" ex:collapsed="true" ex:facetLabel="Strain" ex:expression=".Strain"              ex:scroll="true" ex:sortMode="count"></div> 
    <div  ex:role="facet"  ex:collapsible="true" ex:collapsed="true" ex:facetLabel="Cell Line" ex:expression=".Cell-Line"           ex:scroll="true" ex:facetLabel=""></div>
    <div  ex:role="facet"  ex:collapsible="true" ex:collapsed="true" ex:facetLabel="Tissue" ex:expression=".Tissue"              ex:scroll="true" ex:facetLabel=""></div>
    <div  ex:role="facet"  ex:collapsible="true" ex:collapsed="true" ex:facetLabel="Compound" ex:expression=".Compound"            ex:scroll="true" ex:facetLabel=""></div>
    <div  ex:role="facet"  ex:collapsible="true" ex:collapsed="true" ex:facetLabel="Temperature" ex:expression=".temperature"         ex:scroll="true" ex:facetLabel=""></div>

  </td>
  
<!-- right column: exhibit results -->
  <td id="right-column">

    <div id="data-table"
	 ex:role="view" 
	 ex:viewClass="Tabular" 
	 ex:showToolbox="false"
         ex:maxRows = "20"
	 ex:columnLabels="Dataset,Organism,Technique,Target Element,Assay Factor,Conditions,PI,ID"
	 ex:tableMunger="add_selectall_checkbox"
	 ex:rowStyler="zebraStyler"
	 ex:border="0"
	 ex:cellSpacing="2"
	 ex:cellPadding="3"
	 ex:columns=".label,.organism,.technique,.target,.factor,.Developmental-Stage,.principal_investigator,.submission" 
	 ex:abbreviatedCount="20"
	 >
     <table>
       <tr class="submission" onclick="toggle_tr(this)">
	 <td><input type="checkbox" class="submission-select" ex:id-subcontent="{{.label}}"></input>
	   <span ex:content=".label"></span>
	 </td>
	 <td><span ex:content=".organism"></span></td>
	 <td><span ex:content=".technique"></span></td>
	 <td><span ex:content=".target"></span></td>
	 <td><span ex:content=".factor"></span></td>
	 <td>
	   <span ex:if-exists=".Developmental-Stage">
	     <span ex:content=".Developmental-Stage"></span>
	   </span>
	   <span ex:if-exists=".temperature">
	     <span ex:content=".temperature"></span>
	   </span>
	   <span ex:if-exists=".Compound">
	     <span ex:content=".Compound"></span>
	   </span>
	 </td>
	 <td nowrap="1"><span ex:content=".principal_investigator"></span></td>
	 <td><span ex:content=".submission"></span></td>
       </tr>
     </table>
    </div>
  </td>
</tr>
</table>

</body>
</html>

END

