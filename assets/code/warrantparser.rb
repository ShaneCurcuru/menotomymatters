#!/usr/bin/env ruby
# Read town meeting warrant HTML data into JSON
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

module WarrantParser
  DESCRIPTION = <<-HEREDOC
  WarrantParser: Parse underlying HTML of a town warrant listing from novusagenda.
  https://www.arlingtonma.gov/town-governance/town-meeting using NOVUSAgenda
  - Save raw HTML of underlying agenda
  - Add id='warrantparse' to enclosing TABLE
  - Run this and double-check output is correct
  HEREDOC
  extend self
  require 'nokogiri'
  require 'open-uri'
  require 'json'
  require 'optparse'
  require 'csv'

  NOVUS_URL = 'https://arlington.novusagenda.com/Agendapublic/' # CoverSheet.aspx?ItemID=7186&MeetingID=881
  ERROR = 'error'
  STACK = 'stack'
  LINK_S = 'style1' # styleX are class names from NOVUSAgenda detail page
  TITLE_S = 'style2'
  # 'style3' is always blank; ignore
  TEXT_S = 'style4'
  INSERT_S = 'style5'
  INSERT_BY = 'insertby'
  INSERT_URL = 'inserturl' # See BOARD_MAP
  STYLE_MAP = {
    LINK_S => 'url',
    TITLE_S => 'title',
    TEXT_S => 'text',
    INSERT_S => INSERT_BY,
  }

  BOARD_MAP = { # Note: some articles are inserted by multiple entities; only first one here is used
    /Town Manager/ => 'https://www.arlingtonma.gov/departments/town-manager',
    /Town Moderator/ => 'https://www.arlingtonma.gov/town-governance/town-meeting',
    /Select Board/ => 'https://www.arlingtonma.gov/town-governance/all-boards-and-committees/board-of-selectmen',
    /Redevelopment Board/ => 'https://www.arlingtonma.gov/town-governance/all-boards-and-committees/redevelopment-board',
    /Finance Committee/ => 'https://www.arlingtonma.gov/town-governance/all-boards-and-committees/finance-committee',
    /Town Treasurer/ => 'https://www.arlingtonma.gov/departments/treasurer',
    /Recycling Committee/ => 'https://www.arlingtonma.gov/town-governance/all-boards-and-committees/recycling-committee',
    /Community Preservation Committee/ => 'https://www.arlingtonma.gov/town-governance/all-boards-and-committees/community-preservation-committee',
    /Tree Committee/ => 'https://www.arlingtonma.gov/town-governance/all-boards-and-committees/tree-committee',
    /Envision Arlington/ => 'https://www.arlingtonma.gov/town-governance/all-boards-and-committees/envision-arlington',
    /Minuteman Regional Vocational School District Committee/ => 'http://www.arlington.k12.ma.us/home/',
    /Director of Public Works/ => 'https://www.arlingtonma.gov/departments/public-works',
    /Capital Planning Committee/ => 'https://www.arlingtonma.gov/town-governance/all-boards-and-committees/capital-planning-committee',
    /Director of Human Resources/ => 'https://www.arlingtonma.gov/departments/human-resources',
    /Arlington Conservation Commission/ => 'https://www.arlingtonma.gov/town-governance/all-boards-and-committees/conservation-commission',
    /Council on Aging/ => 'https://www.arlingtonma.gov/departments/health-human-services/council-on-aging',
    /Contributory Retirement Board/ => 'https://www.arlingtonma.gov/town-governance/all-boards-and-committees/retirement-board',
    /ten registered voters/ => 'https://www.arlingtonma.gov/services/request-answer-center?qaframe=answerdetail.aspx%3Finc%3D12067' # (Inserted at the request of Elizabeth Pyle and ten registered voters)
  }

  # Parse a single NOVUSAgenda table row
  # @param node tr from a warrant (may be blank spacer row)
  # @param data to fill in if has valid article data
  def parse_row(row, data)
    cols = row.css('td[class]')
    hash = {}
    cols.each do |col|
      begin
        case col['class']
        when LINK_S # Grab a[href], and text
          a = col.at('a')
          hash['article'] = a.text.strip
          hash['id'] = hash['article'].downcase.gsub(/\s*/, '')
          hash[STYLE_MAP[LINK_S]] = a['href'] # TODO Scrub escapes?
          
        when TITLE_S # Grab all strong text
          strong = col.search('strong')
          strong.each do |s|
            (hash[STYLE_MAP[TITLE_S]] ||= "") << s.text.strip
          end
          
        when TEXT_S # Note: not consistently structured; just grab all text
          hash[STYLE_MAP[TEXT_S]] = col.text.strip # TODO Scrub for cruft?
          
        when INSERT_S # Also annotate with a link if mapping exists
          hash[INSERT_BY] = col.text.gsub(/(\t|\r\n)/, '').strip
          unless hash[INSERT_BY].empty?
            BOARD_MAP.each do |regex, l|
              if regex =~ hash[INSERT_BY]
                hash[INSERT_URL] = l
                break
              end
            end
          end
          
        else
          # No-op: unknown type, we don't use them
        end
      rescue StandardError => e
        data << { 
          ERROR => "ERROR #{e.message}",
          STACK => e.backtrace.join("\n\t"),
          'contents' => col.text.strip.gsub(/(\t|\r\n)/, '')
        }
      end
    end
    data << hash unless hash.empty?
  end
    
  # Parse warrant and output array of hashes of semi-structured data
  # @param f filename to read
  def parse_warrant(f)
    doc = Nokogiri::HTML(File.read(f))
    warrant = doc.css('#warrantparse')
    rows = warrant.css('tr')
    raise StandardError("ERROR: Likely couldn't find TABLE id=warrantparse") if 0 == rows
    puts("... Parsing agenda table rows: #{rows.length}")
    data = []
    rows.each do |row|
      parse_row(row, data)
    end
    return data
  end

  # Process NOVUSAgenda rows into individual articles
  # @param w of three rows in order
  # @return hash of a single article
  # TODO: does not cover error cases or missing rows
  def process_article(w)
    begin
      article = w[0]
      article.merge!(w[1])
      article.merge!(w[2])
      return article
    rescue StandardError => e
      puts "ERROR: #{e.message}\n\y#{e.backtrace.join("\n\t")}"
    end
  end

  # Crossindex articles
  # @param articles list of articles; side effect adds data
  # NOTE: Must be done *after* process_article
  def crossindex(articles)
    begin
      idx = articles.group_by { |v| v[INSERT_URL]}
      # Add related lists to each article
      idx.each do |url, arts|
        next if url.nil?
        articles.select { |a| url.eql?(a[INSERT_URL]) }.each do |article|
          related = []
          arts.each do |x|
            related << x['id']
          end
          article['related'] = related
        end
      end
    rescue StandardError => e
      puts "ERROR: #{e.message}\n\y#{e.backtrace.join("\n\t")}"
    end
  end

  # Add in links to supplments, when we can find them
  # @param articles list of articles; side effect adds data
  # NOTE: Must be done *after* process_article
  def add_supplements(articles)
    articles.each do |article|
      begin
        # Attempt to grab all a's out of official article url
        unless article['url'].empty?
          doc = Nokogiri::HTML(open("#{NOVUS_URL}#{article['url']}"))
          links = doc.search('a')
          unless links.empty?
            article['supplements'] = []
            links.each do |elem|
              if elem['href'] =~ /http/ # Some href are local
                article['supplements'] << { elem['href'] => elem.text.strip }
              else
                article['supplements'] << { "#{NOVUS_URL}#{elem['href']}" => elem.text.strip }
              end
            end
          end
        end
      rescue StandardError => e
        puts "ERROR: #{e.message}\n\y#{e.backtrace.join("\n\t")}"
      end
    end
  end

  # Add in vote results (from spreadsheet)
  # @param articles list of articles; side effect adds data
  # @param votes csv of vote data; id,title,for,against,abstain,status,voted
  #   Where id is matched unless it includes a '#'
  #   Named fields (except title) are copied over to article
  #   If id =~ /#/ append votes[title] to article[amendments]
  # NOTE: Must be done *after* all other article parsing
  def add_votes(articles, votes)
    ctr = 0
    CSV.foreach(votes, headers: true) do |row|
      id, amended = row['id'].split('#')
      if amended # Was an amendment, not original article, annotate it
        articles.select{|a| a['id'] == id}.each do |article|
          article['amendments'] ? article['amendments'] += "#{row['title'].strip.gsub(/\s+/, ' ')}" : article['amendments'] = "#{row['title'].strip.gsub(/\s+/, ' ')}"
          article['amendments'] += ": #{row['status']} (Y #{row['for']}, N #{row['against']}, A #{row['abstain']} on #{row['voted']}), "
        end
      else
        articles.select{|a| a['id'] == id}.each do |article|
          ['for', 'against', 'abstain', 'status', 'voted'].each do |field|
            article[field] = row[field].strip.gsub(/\s+/, ' ') if row[field]
          end
        end
      end
      ctr += 1
    end
    puts "... Added #{ctr} rows of votes or amendments"
  end

  # Normal case: parse and process warrant HTML
  def do_warrant(options)
    options[:file] ||= 'warrant.html'
    options[:out] ||= 'warrant.json'
    puts "Processing: #{options[:file]} into #{options[:out]}"
    flat = parse_warrant(options[:file])
    warrant = []
    puts "... Parsing flat table rows: #{flat.length}"
    flat.each_slice(3).each do |w|
      warrant << process_article(w)
    end
    return warrant
  end

  # Sort by "article" number
  def sort_warrant(warrant)
    return warrant.sort_by.sort_by{ |itm| itm['article'].split(' ')[1].to_i }
  end

  # Link to a committee homepage, if found
  def add_insertlinks(warrant)
    warrant.each do |hash|
      unless hash[INSERT_BY].empty?
        BOARD_MAP.each do |regex, l|
          if regex =~ hash[INSERT_BY]
            hash[INSERT_URL] = l
            break
          end
        end
      end
    end
  end

  # ## ### #### ##### ######
  # Check commandline options (examplar code; overkill for this purpose)
  def parse_commandline
    options = {}
    OptionParser.new do |opts|
      opts.on('-h') { puts "#{DESCRIPTION}\n#{opts}"; exit }
      opts.on('-wWARRANTPDF', '--warrant WARRANTPDF', 'Annual Town Meeting Warrant annotated .html to parse') do |file|
        if File.file?(file)
          options[:file] = file
        else
          raise ArgumentError, "-d #{file} is not a valid file" 
        end
      end
      opts.on('-oOUTFILE.JSON', '--out OUTFILE.JSON', 'Output filename to write as JSON detailed data') do |out|
        options[:out] = out
      end
      opts.on('-iINFILE.JSON', '--infile INFILE.JSON', 'Input JSON filename to annotate more data to (previously created)') do |infile|
        options[:infile] = infile
      end
      opts.on('-vVOTES.CSV', '--votes VOTES.CSV', 'Input CSV filename of voting records to annotate previously created JSON') do |votes|
        options[:votes] = votes
      end
      opts.on('-s', 'ONLY sort a previously created JSON') do |sort|
        options[:sort] = true
      end
      opts.on('-c', 'ONLY add inserturls to committees from a previously created JSON') do |comm|
        options[:comm] = true
      end

      opts.on('-h', '--help', 'Print help for this program') do
        puts opts
        exit
      end
      begin
        opts.parse!
      rescue OptionParser::ParseError => e
        $stderr.puts e
        $stderr.puts opts
        exit 1
      end
    end
    return options
  end

  # ### #### ##### ######
  # Main method for command line use
  if __FILE__ == $PROGRAM_NAME
    options = parse_commandline
    warrant = []
    
    if options[:comm] # Only add links
      options[:infile] ||= 'warrant.json'
      options[:out] ||= 'warrant-links.json' # Make it a separate file for comparison
      puts "Parsing existing file: #{options[:infile]}"
      warrant = JSON.parse(File.read(options[:infile]))
      add_insertlinks(warrant)
    elsif options[:sort] # Only sort
      options[:infile] ||= 'warrant.json'
      options[:out] ||= 'warrant-sorted.json' # Make it a separate file for comparison
      puts "Parsing existing file: #{options[:infile]}"
      warrant = JSON.parse(File.read(options[:infile]))
      warrant = sort_warrant(warrant)
    elsif options[:votes]
      # Append final voting data to existing JSON
      options[:infile] ||= 'warrant.json'
      options[:out] ||= 'warrant-votes.json' # Make it a separate file for comparison
      puts "Parsing existing file: #{options[:infile]}, adding votes: #{options[:votes]}"
      warrant = JSON.parse(File.read(options[:infile]))
      add_votes(warrant, options[:votes])
    else
      # Default processing is to read HTML and process all data
      warrant = do_warrant(options)
      crossindex(warrant)
      add_supplements(warrant)
    end
    
    puts "... Outputting warrant articles: #{warrant.length}"
    File.open("#{options[:out]}", "w") do |f|
      f.puts JSON.pretty_generate(warrant)
    end
  end
end


