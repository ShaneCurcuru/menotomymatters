#!/usr/bin/env ruby
# Read town agenda materials HTML data into JSON
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

module AgendaParser
  DESCRIPTION = <<-HEREDOC
  AgendaParser: Parse underlying HTML of various NOVUSagenda pages into json crossindexed structure.
  Users go to a board agenda page for ARB:
  https://www.arlingtonma.gov/town-governance/all-boards-and-committees/redevelopment-board/agendas-minutes
  
  Which embeds an IFrame of this, parseable by parse_list_html() 
  https://arlington.novusagenda.com/agendapublic/meetingsresponsive.aspx?MeetingType=45
  
  Which points to an Online Agenda of: parseable by parse_arb_agenda()
  https://arlington.novusagenda.com/agendapublic/MeetingView.aspx?MeetingID=1043&MinutesMeetingID=-1&doctype=Agenda
  
  Which may have a "Correspondence recieved" page of: (not yet done)
  https://arlington.novusagenda.com/agendapublic/CoverSheet.aspx?ItemID=8825&MeetingID=1043
  
  ARB videos from ACMi
  https://acmi.tv/videos/redevelopment-board-meeting-january-27-2020/
  https://acmi.tv/videos/redevelopment-board-meeting-november-18-2019/
  https://acmi.tv/videos/select-board-meeting-may-4-2020/
  
  Note: various manual cleanup is also done, especially when agenda text changes subtly or doesn't include specific markers.
  HEREDOC
  extend self
  require 'nokogiri'
  require 'open-uri'
  require 'json'
  require 'optparse'
  require "net/http"
  require "uri"
  
  ACMI_ARB_URL = 'https://acmi.tv/videos/redevelopment-board-meeting-' # january-27-2020; or select-board etc.
  NOVUS_URL = 'https://arlington.novusagenda.com/Agendapublic/' # CoverSheet.aspx?ItemID=7186&MeetingID=881
  ERROR = 'error'
  STACK = 'stack'
  NOTICE = 'notice'
  ROWS = 'rows'
  ITEMS = 'items'
  ITEMNUM = 'num'
  ITEMLINK = 'url'
  TITLE = 'title'
  DETAILS = 'details'
  START_TIME = 'time'
  LOCATION = 'location'
  VIEWURL = 'viewurl'
  PDFURL = 'pdfurl'
  MINUTESURL = 'minurl'
  DATE = 'date'
  ISODATE = 'isodate'
  DOCKETS = 'dockets'
  AGENDA = 'agenda'
  AGENDAS = 'agendas'
  BYLAWS = 'bylaws'
  ARBHTML = '-arb.html'
  CORRESPONDENCE = 'correspondence'
  CORRESPONDENCE_MATCH = /Correspondence received/i
  DOCKET_MATCH = /docket.{1,2}(\d\d\d\d),?([^*]+)/i
  ARB_BYLAW_MATCH = /ARTICLE (\d+) ZONING/
  ARB_BYLAW_MATCH2 = /ARTICLE \d+ ZONING [^a-z]*/
  BOGUS_CHAR = " " # Not sure where this comes from in the html
  CROSSINDEX = 'crossindex'
  
  # Parse an agenda listing html item row 
  # @param row of tr holding the item
  # @return hash of this agenda's links
  def parse_list_item(row)
    meeting = {}
    begin
      meeting[DATE] = row.css('td:nth-child(2)').text.strip
      meeting[ISODATE] = Date.strptime(meeting[DATE], "%m/%d/%y")
      meeting[TITLE] = row.css('td:nth-child(3) label').text.strip
      meeting[LOCATION] = row.css('td:nth-child(4)').text.strip
      a = row.css('td:nth-child(5) a')
      if a.any?
        meeting[VIEWURL] = a[0]['onclick'].split("'")[1]
      end
      a = row.css('td:nth-child(6) a')
      if a.any?
        meeting[PDFURL] = a[0]['href']
      end
      a = row.css('td:nth-child(7) a')
      if a.any?
        meeting[MINUTESURL] = a[0]['href']
      end
    rescue StandardError => e
      meeting[ERROR] = e.message
      meeting[STACK] = e.backtrace.join("\n\t")
    end
    return meeting
  end
  
  # Parse an meeting agenda listing html and output array of hashes of semi-structured data
  # Works on similar to: view-source:https://arlington.novusagenda.com/agendapublic/meetingsresponsive.aspx?MeetingType=45
  # @param io to parse as html of the detail agenda page
  # @return array of agenda info hashes
  def parse_list_html(io)
    data = []
    begin
      doc = Nokogiri::HTML(io)
      table = doc.css('#myTabContent table')[0] # First table inside the myTabContent div
      rows = table.css('tr').drop(1) # Remove the header row
      puts("parse_agenda_list() Parsing agenda table, children #{rows.length}")
      rows.each do |row|
        next if 'collapse' == row['class'] # Skip duplicate mobile-only rows
        data << parse_list_item(row)
      end
    rescue StandardError => e
      data = e.message
      data = e.backtrace.join("\n\t")
    end
    return data
  end
  
  # Download each meeting agenda from a preloaded json listing
  # @param dir to place files
  # @param json hash from parse_list_html() output
  # @return array of agenda detail hashes, annotated
  # Side effect: creates local dir/2020-05-05-arb.html files
  def download_agendas(dir, json)
    begin
      puts("download_agendas() Downloading agenda list of meetings #{json.length} into #{dir}")
      json.each do |mtg|
        # Save each file out
        puts "Outputting file #{mtg[ISODATE]}#{ARBHTML}"
        File.open(File.join(dir, "#{mtg[ISODATE]}#{ARBHTML}"), "w") do |f|
          f.write(open(NOVUS_URL + mtg[VIEWURL]).read)
        end
      end
    rescue StandardError => e
      json << e.message
      json << e.backtrace.join("\n\t")
    end
    return json
  end
  
  # Parse each ARB agenda from a predownloaded directory
  # This is probably generic with Select Board too
  # @param dir to scan for *.html files
  # @param io of the json details
  # @return array of agenda detail hashes, annotated
  def parse_arb_agendas(dir, json)
    errors = []
    begin
      puts("parse_arb_agendas() Parsing agendas # #{json.length} from #{dir}")
      json.each do |mtg|
        # Annotate each item by parsing corresponding file
        fn = File.join(dir, "#{mtg[ISODATE]}#{ARBHTML}")
        if File.file?(fn)
          mtg[AGENDA] = parse_arb_agenda(File.open(fn), fn)
        else
          mtg[ERROR] = "File not found: #{fn}"
        end
      end
    rescue StandardError => e
      errors << e.message
      errors << e.backtrace.join("\n\t")
    end
    json << errors if errors.any?
    return json
  end
  
  # Parse an ARB agenda page and output array of hashes of semi-structured data
  # This is customized to the specific ARB agenda formats from 2020-2018
  # @param io stream to read
  # @param id identifier of stream (filename or URL)
  # @return data hash listing agenda metadata and details; includes ERROR key if any
  def parse_arb_agenda(io, id)
    data = {}
    begin
      doc = Nokogiri::HTML(io)
      tables = doc.css('td > table') # A table inside a cell
      puts("... Parsing agenda table rows: #{tables.length} for #{id}")
      raise ArgumentError.new("Agenda data not found; perhaps meeting was cancelled?") if tables.length < 3
      # Grab header info from first table
      data[NOTICE] = tables[0].css("[colspan]#column1").text.strip.gsub(/\s+/, ' ')
      # Skip second table (just spacer)
      # Third table is rows of embedded data
      rows = tables[2].elements
      data[ROWS] = rows.length
      data[ITEMS] = []
      tmp = rows.first
      header = tmp.next_element
      detail = header.next_element
      while detail do 
        a = {}
        dockets = {}
        bylaws = {}  
        # Parse header row, including number, title, and possible link
        style3 = header.css(".style3")
        a[ITEMNUM] = style3[0].text
        a[TITLE] = style3[1].text.strip.gsub(/\s+/, ' ')
        style3link = style3.css("a")
        a[ITEMLINK] = style3link[0]['href'] if style3link.any?
        
        # Parse sub-table of details; just nned two cells within subtable
        cells = detail.css("tbody > tr > td")
        if cells.length > 1
          # Split the time and details out
          a[START_TIME] = cells[0].text.strip.gsub(/\s+/, ' ')
          text = ''
          # Various types of detail table rows exist for ARB agendas
          # Several <p> elements
          # Single chunk of text (usually short)
          # Single TD with text and <br/> separated lines
          # No table at all, just a .style4 td with text inside
          hasparas = cells[1].css('p')
          if hasparas.any?
            paras = cells[1].elements
            paras.each do |p|
              text += p.text.strip.gsub(/\s+/, ' ').gsub('•',"\n- ") + "\n\n"
              strongs = p.css('strong')
              strongs.each do |txt| # Parse docket numbers or bylaw numbers
                dmatch = DOCKET_MATCH.match(txt)
                dockets[dmatch.captures[0]] = dmatch.captures[1].strip if dmatch
                bmatch = ARB_BYLAW_MATCH.match(txt)
                bylaws[bmatch[1]] = txt.text if bmatch
              end
            end
          else
            text = cells[1].text.strip.gsub(/\s+/, ' ').gsub('•',"\n- ")
            strongs = cells[1].css('strong')
            strongs.each do |txt| # Parse docket number and remainder
              dmatch = DOCKET_MATCH.match(txt)
              dockets[dmatch.captures[0]] = dmatch.captures[1].strip if dmatch
              bmatch = ARB_BYLAW_MATCH.match(txt)
              bylaws[bmatch[1]] = txt.text if bmatch
            end
          end
          d = text.scan(/docket.{1,2}(\d\d\d\d)/i) # Fallback to catch unsual docket discussions
          d.each do |dd|
            dockets[dd[0]] = '' unless dockets.has_key?(dd[0])
          end
          a[DETAILS] = text
          a[DOCKETS] = dockets if dockets.any?
          a[BYLAWS] = bylaws if bylaws.any?
        else
          # Simplistic case where there's only one cell, or no subtable at all
          if cells.any?
            a[DETAILS] = cells[0].text.strip.gsub(/\s+/, ' ').gsub('•',"\n- ")
          else
            # Fallback to simply taking the td content itself; leave linebreaks
            style4 = detail.css(".style4")
            a[DETAILS] = style4[0].text.strip.gsub(/[ \t]+/, ' ').gsub('•',"\n- ")
          end
        end
        # Backup scan for bylaws, they are often in different formats
        unless a.has_key?(BYLAWS)
          tmp = a[DETAILS].scan(ARB_BYLAW_MATCH2)
          tmp.each do |bmatch|
            bylaws[ARB_BYLAW_MATCH.match(bmatch)[1]] = bmatch
          end
          a[BYLAWS] = bylaws if bylaws.any?
        end
        # Backup scan for dockets in titles
        if dockets.empty?
          dmatch = DOCKET_MATCH.match(a[TITLE])
          dockets[dmatch.captures[0]] = dmatch.captures[1].strip if dmatch
          a[DOCKETS] = dockets if dockets.any?
        end
        # Organize any correspondence
        if CORRESPONDENCE_MATCH =~ a[TITLE] 
          arr = a[DETAILS].sub(CORRESPONDENCE_MATCH.source, '').sub(/from:?\s?/, '').gsub(BOGUS_CHAR, '').strip.split(/\r?\n+/)
          a[CORRESPONDENCE] = arr.reject{|frm| frm.length < 1} if arr.any?
        end
        # Stuff our item into array
        data[ITEMS] << a
        header = detail.next_element
        detail = nil
        detail = header.next_element if header    
      end
    rescue StandardError => e
      data[ERROR] = "#{id} #{e.message}"
      data[STACK] = e.backtrace.join("\n\t")
    end
    return data
  end
  
  # Crossindex an existing json of parsed agendas
  # @param hash to annotate
  # Side effect: adds metadata at head and in items
  def crossindex_arb(json)
    errors = []
    dockets = {}
    begin
      puts("crossindex_arb() Parsing agendas # #{json.length}")
      crossindex = {}
      crossindex[TITLE] = CROSSINDEX
      meetings = json.each
      meetings.each do |meeting|
        agenda = meeting[AGENDA]
        next unless agenda 
        next unless agenda.has_key?(ITEMS)
        agenda[ITEMS].each do |item|
          if item.has_key?(DOCKETS)
            item[DOCKETS].each do |d, val|
              # Cache and fillin missing addresses (best attempt)
              if dockets.has_key?(d)
                if ''.eql?(dockets[d])
                  dockets[d] = val
                elsif ''.eql?(val)
                  item[DOCKETS][d] = dockets[d]
                elsif ! dockets[d].eql?(val)
                  puts "DEBUG: Mismatched addresses(#{d}, #{meeting[ISODATE]}, #{item[ITEMNUM]}): |#{dockets[d]}|<>|#{item[DOCKETS][d]}|"
                end
              else
                dockets[d] = val
              end
              # OMG I really need more coffee, this is spaghetti
              if crossindex.has_key?(d)
                crossindex[d]['meetings'] << meeting[ISODATE]
              else
                crossindex[d] = {}
                crossindex[d]['address'] = val
                crossindex[d]['meetings'] = [meeting[ISODATE]]
              end
            end
          end
        end
      end
    rescue StandardError => e
      errors << e.message
      errors << e.backtrace.join("\n\t")
    end
    json << crossindex 
    json << errors if errors.any?
    return json
  end
  
  # Changed data format to make display simpler
  # Transform the originally parsed array w/crossindex into a single hash
  def transform_arb(json)
    transformed = {}
    puts("transform_arb() Parsing agendas # #{json.length}")
    agendas, crossindex = json.partition { |h| h.has_key?(ISODATE) }
    agendas.each do |agenda|
      transformed[agenda[ISODATE]] = agenda
    end
    transformed[CROSSINDEX] = {}
    crossindex[0].each do |k, val|
      puts "DEBUG (#{k}) #{val}"
      if val.kind_of?(Hash)
        transformed[CROSSINDEX][k] = {} # Force new ordering in hash
        transformed[CROSSINDEX][k]['address'] = val['address']
        transformed[CROSSINDEX][k]['purpose'] = ''
        transformed[CROSSINDEX][k]['owner'] = ''
        transformed[CROSSINDEX][k]['meetings'] = val['meetings']
      else
        # no-op, drop string
      end
    end
    return transformed
  end
  
  # Add ACMi Video links
  def add_video(json)
    puts("add_video_arb() Parsing agendas # #{json.length}")
    json.each do |key, agenda|
      if agenda.has_key?(DATE)
        # Cleanup and check video availability first
        agenda.delete('video')
        url = ACMI_ARB_URL + Date.strptime(agenda[DATE], "%m/%d/%y").strftime("%B-%-d-%Y").downcase + '/'
        puts "DEBUG: add_video() #{url}"
        rsp = Net::HTTP.get_response(URI.parse(url))
        if rsp.kind_of?(Net::HTTPSuccess)
          agenda['video'] = url
        end
      end
    end
    return json
  end
  
  # ## ### #### ##### ######
  # Check commandline options
  def parse_commandline
    options = {}
    OptionParser.new do |opts|
      opts.on('-h', '--help', 'Print help for this program') { puts "#{DESCRIPTION}\n#{opts}"; exit }
      opts.on('-iINPUT', '--input INPUTFILE', 'Input file to use for current operation') do |file|
        if File.file?(file)
          options[:file] = file
        else
          raise ArgumentError, "-a #{file} is not a valid file" 
        end
      end
      opts.on('-oOUTFILE.JSON', '--out OUTFILE.JSON', 'Output filename to write as JSON detailed data (default: agenda.json)') do |out|
        options[:out] = out
      end
      opts.on('-uAGENDAURL', '--url AGENDA.COM/PATH', 'Agenda URL to parse online') do |url|
        options[:url] = url
      end
      opts.on('-t', 'Transform agenda format to hash/hash') do |transform|
        options[:transform] = true
      end
      opts.on('-dDIR', '--dir DIR', 'Working directory for downloaded files') do |dir|
        if File.directory?(dir)
          options[:dir] = dir
        else
          raise ArgumentError, "-d #{dir} is not a valid file" 
        end
      end
      opts.on('-q', 'Read agenda HTML listing and create agenda json listing') do |phtmllist|
        options[:phtmllist] = true
      end
      opts.on('-x', 'Read agenda json listing and download to individual agendas linked therefrom') do |dld|
        options[:dld] = true
      end
      opts.on('-j', 'Read agenda json listing and parse each file in :dir into individual agendas') do |pjson|
        options[:pjson] = true
      end
      opts.on('-c', 'Only crossindex existing arb agendas json') do |crossindexarb|
        options[:crossindexarb] = true
      end
      opts.on('-v', 'Only add video links existing agendas json') do |video|
        options[:video] = true
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
    options[:out] ||= 'agenda.json'
    io = nil
    ioname = ''
    if options.has_key?(:file)
      ioname = options[:file]
      io = File.read(ioname)
    elsif options.has_key?(:url)
      ioname = options[:url]
      io = open(ioname)
    else
      puts "WARNING: No apparent -i or -u input provided, expect to crash!"
    end
    if options.has_key?(:video)
      puts "Adding video links to list json #{ioname}"
      agenda = add_video(JSON.parse(io))
    elsif options.has_key?(:transform)
      puts "Transforming ARB agenda list json #{ioname} to hash"
      agenda = transform_arb(JSON.parse(io))
    elsif options.has_key?(:crossindexarb)
      puts "Crossindexing ARB agenda list json #{ioname}"
      agenda = crossindex_arb(JSON.parse(io))
    elsif options.has_key?(:phtmllist)
      puts "Parsing agenda list html #{ioname}"
      agenda = parse_list_html(io)
    elsif options.has_key?(:dld)
      puts "Downloading agenda list json #{ioname} into #{options[:dir]}"
      agenda = download_agendas(options[:dir], JSON.parse(io))
    elsif options.has_key?(:pjson)
      puts "Parsing agenda list json #{ioname} from #{options[:dir]}"
      agenda = parse_arb_agendas(options[:dir], JSON.parse(io))
    end
    puts "Outputting file #{options[:out]}"
    File.open("#{options[:out]}", "w") do |f|
      f.puts JSON.pretty_generate(agenda)
    end
  end
end
