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
  require 'json'
  require 'optparse'
  require 'date'

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
    data = []
    begin
      doc = Nokogiri::HTML(File.read(f))
      warrant = doc.css('#warrantparse')
      rows = warrant.css('tr')
      (0 == rows) ? puts("ERROR: Likely couldn't find TABLE id=warrantparse") : puts("... Parsing agenda table rows: #{rows.length}")
      rows.each do |row|
        parse_row(row, data)
      end
    rescue StandardError => e
      data << { 
        ERROR => "ERROR #{e.message}",
        STACK => e.backtrace.join("\n\t")
      }
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
    warrant = do_warrant(options)
    crossindex(warrant)
    puts "... Outputting warrant articles: #{warrant.length}"
    File.open("#{options[:out]}", "w") do |f|
      f.puts JSON.pretty_generate(warrant)
    end
  end
end


