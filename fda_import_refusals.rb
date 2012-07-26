#### Preparing tools

# Ruby and many other programming languages allow one to load
# additional code of which may be called upon when writing one's code.
# Below several software libraries will be loaded for the task at hand.

# [open-uri](http://ruby-doc.org/stdlib/libdoc/open-uri/rdoc/index.html) is part of the [Ruby Standard Library](http://ruby-doc.org/stdlib/) (stdlib). The stdlib is a set of software libraries
# which are included with every installation of Ruby, but not loaded by default.
require "open-uri"

# [Rubygems](http://rubygems.org/) is a package manager for Ruby. It's a convenient way to get access to ruby 
# software libraries dubbed "gems".  Rubygems must be `require`d before any other gems can be loaded.
require "rubygems"

# [Nokogiri](http://nokogiri.org/) is an XML and HTML processing gem. It will be doing much of our work for us. 
require "nokogiri"

#### Data Extraction

# In order to gather the details of a single refusal from its webpage, 
# we have identified the ID of the table holding our data (e.g. "details") 
# on the refusal's page, through a means such as the Google Chrome web inspector.  
# After using Nokogiri to gain access to the table, we can iterate over 
# the table's rows to collect each field and value, and return a hash
# associating fields and values for each record.
# We begin with a description of the behavior needed grouped into methods.

# The gather_refusal method requires that a page of HTML parsed using
# Nokogiri will be passed to it.  Within the method, HTML page will be
# stored and referred to as `html`.
def gather_refusal(html)

  # `table#details > tr` specifies all of the table rows (the `tr`s)
  # directly belonging to the `details` table.
  # `table#details` indicates that we're looking for a table with the
  # ID `details`, and the `>` symbol indicates that we wish only
  # to inspect the HTML tags immediately belonging to the table.
  rows = html.css("table#details > tr")
  refusal_data = {}

  # We gather only the rows directly belonging to the `table#details`
  # because its last row (which we pop off of the list of rows we've gathered)
  # itself includes a table.  Leaving out the `>` symbol would gather *all* the
  # rows anywhere below `table#details` (and consequently we'd have two different
  # types of data rows in our list).  Instead we'll remove the final row from our list
  # and pass it into a seperate "gather_charges" data extraction method.
  refusal_data["charges"] = gather_charges(rows.pop)
  
  # For the rest of the rows, which consist of a field name and a value,
  # we'll take each row one at a time, and store the value by its
  # field name in the hash we named `refusal_data` above.
  rows.each do |row|
    field = row.css("th").text.strip
    datum = row.css("td").text.strip
    refusal_data[field] = datum
  end
  return refusal_data
end

# Gathering the specific charges for a refusal is similar to the extraction
# process noted in the `gather_refusal` method above.  Where this extraction
# differs is that the data in the charges table is oriented differently.  Each
# field name is stored in a single header row, and each successive row is a
# single charge record.
def gather_charges(html)
  rows    = html.css("table tr")
  charges = []

  # remove the first header row from our list
  # extract the name of the fields in each of the `th` cells.
  header  = rows.shift
  fields  = header.css('th').map{ |cell| cell.text.strip }
  
  # Collect the values in each row into a `data` array
  # and interleave our list of fields with the list of values
  # using [`zip`]().
  rows.each do |row|
    data = row.css("td").map{ |cell| cell.text.strip }
    charges.push Hash[fields.zip(data)]
  end
  return charges
end

#### Gathering links for crawling

# Moving beyond extracting data out of a single page using
# `gather_refusal` requires the ability to gather and open
# links from the index pages the FDA uses to organize their
# reports.

# `gather_links` takes Nokogiri parsed HTML and extracts
# a list of links that can be used to continue scraping.
# This method assumes that the links are contained within
# a `ul` (unordered list).  Users can optionally pass in a
# `base_url` 
def gather_links(html, base_url=nil)
  contents = html.css("span#user_provided")
  address_list = contents.css("ul")
  addresses = address_list.css("a").map do |link|
    link_address = link.attributes["href"].text
    link_address = base_url + link_address unless link_address =~ /^http/
  end
end

# `gather_table_links`, like `gather_links` takes some HTML
# and extracts a list of links for the scraper to continue
# exploring.
def gather_table_links(html, base_url=nil)
  contents = html.css("span#user_provided")
  address_list = contents.css("table")
  addresses = address_list.css("a").map do |link|
    link_address = link.attributes["href"].text
    link_address = base_url + link_address unless link_address =~ /^http/
  end
end

#### Crawler

# The `crawl` method is the automating component for this scraper.
# Starting at any page on the FDA's [Import Refusals Report](http://www.accessdata.fda.gov/scripts/importrefusals/)
# `crawl` will extract data or links, and open and scrape the contents
# of each successive link it finds.
# 
# N.B. `crawl` is a recursive method, which means that it
# has a mechanism to call itself.  Recursive methods must
# be written with care, but are good ways to automate
# repetative behavior in a well defined way.
def crawl(address)
  # first we must ensure that our address is a URI object
  address = URI.parse(address) unless address.kind_of? URI
  puts address

  # Using `open-uri`'s `open` method, we will fetch the contents
  # of the page located at `address` and parse it with Nokogiri.
  html = Nokogiri::HTML(open(address).read)
  
  # Using Nokogiri, the FDA page template can be ignored by
  # narrowing down to just the user provided contents of the
  # page (as indicated by the CSS selector provided)
  contents = html.css("span#user_provided")
  if contents.css("ul").size > 0
    return gather_links(html, address).map{ |link| crawl(link) }
  elsif contents.css("table.new_layout").size > 0 or contents.css("table#country").size > 0
    return gather_table_links(html, address).map{ |link| crawl(link) }
  elsif html.css("span#user_provided").css("table#details").size > 0
    return gather_refusal(html)
  end
end

# Actually do the crawling!
data = crawl("http://www.accessdata.fda.gov/scripts/importrefusals/ir_months.cfm?LType=C").flatten

# N.B.
# The script at this point does nothing further with the data.
# Additional code will be written to take the data and dump it 
# into a database or out to a CSV.
# 
# Apologies for the inconvenience.
# 
# – [Ted Han](mailto:ted@knowtheory.net) ([@knowtheory](http://twitter.com/knowtheory))