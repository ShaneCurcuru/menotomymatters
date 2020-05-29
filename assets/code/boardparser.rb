#!/usr/bin/env ruby
# Read town agenda materials HTML listing data into JSON
# Copyright (c) 2020 Shane Curcuru
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module BoardParser
  DESCRIPTION = <<-HEREDOC
  BoardParser: Parse board listings from arlingtonma.gov website
  HEREDOC
  extend self
  require 'nokogiri'
  require 'open-uri'
  require 'net/http'
  require 'uri'
  require 'json'
  require_relative 'agendautils'

  ALLBOARDS_ROOT = 'https://www.arlingtonma.gov/town-governance/all-boards-and-committees/'
  
  # Download a committee listing html page (or use cached files)
  # @param dir to place files
  # @param json listing all committees (manually generated from https://www.arlingtonma.gov/town-governance/all-boards-and-committees)
  # @return hash of committee list, annotated with filename; or with error
  # Side effect: creates local dir/committee-name.html files
  def download_boardpages(dir, cttees)
    puts "WARNING: No working directory #{dir} provided, using ." unless dir
    puts("#{__method__.to_s}() Downloading committee homepages # #{cttees.length} into #{dir}")
    cttees.each do |url, cttee|
      # Only process committees that have normal pages
      next unless url.start_with?(ALLBOARDS_ROOT)
      cttee.has_key?(AgendaUtils::FILENAME) ? fn = cttee[AgendaUtils::FILENAME] : fn = File.join(dir, "#{url.slice(ALLBOARDS_ROOT.length..)}.html")
      if File.file?(fn)
        puts("Found cached file #{fn}")
        cttee[AgendaUtils::FILENAME] = fn unless cttee.has_key?(AgendaUtils::FILENAME)
      else    
        puts("Downloading file #{fn}")
        begin
          File.open(fn, "w") do |f|
            f.write(open(url).read)
          end
          cttee[AgendaUtils::FILENAME] = fn
        rescue StandardError => e
          cttee[AgendaUtils::ERROR] = e.message
          cttee[AgendaUtils::STACK] = e.backtrace.join("\n\t")
        end
      end
    end
    return cttees
  end

  # Parse previously downloaded committee homepages
  # @param dir to scan for committee.html files
  # @param cttees json of the committee listings; either preparsed or just notice listings
  # @return hash of all data, annotated
  def parse_committees(dir, cttees)
    hash = {}
    begin
      puts("#{__method__.to_s}() Parsing committees # #{cttees.length} from #{dir}")
      cttees.each do |url, cttee|
          # Annotate each item by parsing corresponding file
          cttee['id'] = url.slice(ALLBOARDS_ROOT.length..)
          cttee.has_key?(AgendaUtils::FILENAME) ? fn = cttee[AgendaUtils::FILENAME] : fn = File.join(dir, "#{cttee['id']}.html")
          if File.file?(fn)     
            parse_committee(File.open(fn), cttee)
          else
            cttee[AgendaUtils::ERROR] = "File not found: #{fn}"
          end
        hash[url] = cttee 
      end
    rescue StandardError => e
      puts(e.message)
      puts(e.backtrace.join("\n\t"))
    end
    return hash
  end

  LINK_MAP = {
    'committee-calendar' => 'calendar',
    'agendas-minutes' => 'agenda',
    'agendas-and-minutes' => 'agenda',
    'policies' => 'policy',
    'news' => 'news',
    'statutory-authority' => 'authority',
    'appointed-positions' => 'appointed',
    'license-permits' => 'permits'
  }
  # Parse a committee homepage for best attempt at data
  # @param io stream of html to parse
  # @param hash of data to annotate - Side Effect adds keys
  def parse_committee(io, cttee)
    begin
      doc = Nokogiri::HTML(io)
      # Grab topline links
      nav = doc.css('.sidenav li:not([class])')
      if nav.any?
        cttee['links'] = {}
        nav.each do |li|
          a = li.css('a')[0] # Limitation: only take first link (shouldn't be any others normally)
          # Map commonly used links to top level fields if not already done
          linktext = a.text.strip.downcase.gsub(/[^\p{Word}\- ]/, '').gsub(/\s+/, '-')
          if LINK_MAP.has_key?(linktext)
            cttee[LINK_MAP[linktext]] ||= a['href'] # Only set if not already set 
          else
            cttee['links'][linktext] = a['href']
          end
        end
      end
      members = doc.css('.staff_box > div > ul > li > a')
      if members.any?
        cttee['members'] = {}
        members.each do |a|
          cttee['members'][a.text.strip] = a['href']
        end
      end
      # news = doc.css('.news_box') already covered by "links" "news"
      # events = doc.css('.events_box') already covered by "links" "committee-calendar"
      blobs = ''
      links = []
      chunks = doc.css('.normal_content_area')
      chunks[0].children.each do |node| # Only process first content area (second one is file viewers)
        parse_node(node, blobs, links)
      end
      if blobs.empty?
        return nil
      else
        cttee['urls'] = links if links.any?
        # # Delete any "Free viewers are required for some of the attached documents" section to end
        # cttee['description'] = blobs.sub(/Free viewers are required for some of the attached documents.*/, '')
        # Attempt to trim unneeded blank lines and excess space
        cttee['description'] = blobs.gsub(AgendaUtils::NBSP, ' ').gsub(/\n\s+\n/, "\n\n").gsub(/\n{3,8}/, "\n\n").gsub(/\n\s{3,}/, "\n ")
      end
    rescue StandardError => e
      cttee[AgendaUtils::ERROR] = e.message
      cttee[AgendaUtils::STACK] = e.backtrace.join("\n\t")
    end
  end

  # Recursively parse contents of a td cell or p element
  # @param node of td cell
  # @param blobs string to aggregate any markdown to
  # @param links array to aggregate any hrefs to
  def parse_node(node, blobs, links)
    if node.text?
      blobs << node.content.strip unless node.content.strip.empty?
    else
      # Process elements
      case node.name
      when 'a'
        links << node['href']
        blobs << "<a href='#{node['href']}'>#{node.content.strip}</a> "
      when 'p'
        node.children.each do |child|
          parse_node(child, blobs, links)
        end
        blobs << "  \n" # Use GFM linebreak
      when 'ul'
        parse_ul(node, blobs, links)
      when 'h1', 'h2', 'h3', 'h4'
        blobs << "#####{node.content.strip}  \n" # Arbitrarily make any headers #### level
      else
        # No-op: ignore other nodes; either not needed or we already got contents
      end # case
    end # if
  end

  # Parse just a flat ul element (grabbing text from each li)
  # @param node of ul cell
  # @param blobs string to aggregate any markdown to
  # @param links array to aggregate any hrefs to
  def parse_ul(node, blobs, links)
    blobs << "\n" # Ensure markdown treats as list
    node.children.each do |child|
      if 'li'.eql?(child.name)
        blobs << "\n- #{child.content.strip}" unless child.content.strip.empty?
      end
    end
    blobs << "\n\n" # Ensure markdown treats as list
  end

  # Crossindex a hash of parsed committees vis-a-vis existing index
  # @param cttees to index
  # @return crossindex hash of all data combined
  def post_process(cttees)
    begin
      puts("#{__method__.to_s}() crossindexing committees # #{cttees.length} ")
      idx = {}
      cttees.each do |key, cttee|
        # Create separate crossindex by topics
        cttee['topics'].each do |t|
          unless idx.has_key?(t)
            idx[t] = {}
          end
          idx[t][cttee['id']] = cttee['title']
        end
      end
    rescue StandardError => e
      puts(e.message)
      puts(e.backtrace.join("\n\t"))
    end
    return idx
  end

  # CPFIELDS = [
  #   "tracker",
  #   "location",
  #   "map",
  #   "day",
  #   "time",
  #   "count",
  #   "created",
  #   "appoints",
  #   "video",
  #   "calendar",
  #   "feed",
  #   "agenda",
  #   "budget",
  #   "policy",
  #   "bylaw",
  #   "desc1",
  #   "desc2"
  # ]
  # # Merge in existing manual data to full list
  # def merge_hashes(olds, news)
  #   # Return full hash, including all appropraite fields from each side
  #   hash = {}
  #   news.each do |key, cttee|
  #     hash[key] = {}
  #     if olds.has_key?(key)
  #       # copy over all non-blank data in specific order; new then old
  #       hash[key]['title'] = cttee['title']
  #       hash[key]['topics'] = cttee['topics']
  #       hash[key]['filename'] = cttee['filename']
  #       CPFIELDS.each do |field|
  #         hash[key][field] = olds[key][field]
  #       end
  #     else
  #       # just copy new data
  #       cttee.each do |k,v|
  #         hash[key][k] = v
  #       end
  #     end
  #   end
  #   return hash
  # end

  # ### #### ##### ######
  # Main method for command line use
  if __FILE__ == $PROGRAM_NAME
    options = {}
    options[:input] = '_data/townhall.json'
    options[:out] = '_data/townhall-index.json'
    options[:dir] = '_agendas'
    puts "Processing committee files #{options[:input]} into dir: #{options[:dir]}"
#    data = download_boardpages(options[:dir], JSON.parse(File.read(options[:input])))
#    data = parse_committees(options[:dir], JSON.parse(File.read(options[:input])))
    data = post_process(JSON.parse(File.read(options[:input])))    
    puts "Outputting file #{options[:out]}"
    File.open("#{options[:out]}", "w") do |f|
      f.puts JSON.pretty_generate(data)
    end
  end
end
