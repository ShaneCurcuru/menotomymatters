#!/usr/bin/env ruby
# Screen scrape various NOVUSAgenda materials into json structures
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
  AgendaParser: Parse various Agendas (ARB, Select, etc) from NOVUSagenda system
  Common usage:
  - Manually download a listing of agendas you're interested in as flat .html file, from an iframe page like this:
    https://arlington.novusagenda.com/agendapublic/meetingsresponsive.aspx?MeetingType=45 ARB
    https://arlington.novusagenda.com/agendapublic/meetingsresponsive.aspx?MeetingType=50 Select board
  - Feed the resulting html into 
      AgendaUtils.parse_meeting_list() to get a meeting agenda listing
  - Feed that data into AgendaUtils.download_meetings() to actually copy individual HTML of agendas locally 
      This ensures if you need to re-parse later you don't need to keep downloading
  - Feed that listing and directory into AgendaUtils.parse_agendas() for your type

  Note: various manual cleanup may be needed; some board's agendas are irregularly formatted.
  HEREDOC
  extend self
  require 'open-uri'
  require 'json'
  require 'optparse'
  require_relative 'arbparser'
  require_relative 'selectparser'

  # Parse an meeting agenda listing html and output array of hashes of semi-structured data
  # Download html source from: view-source:https://arlington.novusagenda.com/agendapublic/meetingsresponsive.aspx?MeetingType=45
  #   after selecting the meetings you want
  # @param io to parse as html of the detail agenda page
  # @return hash by ISODATE of agenda metadata hashes
  def parse_meeting_list(io)
    meetings = {}
    doc = Nokogiri::HTML(io)
    table = doc.css('#myTabContent table')[0] # First table inside the myTabContent div
    rows = table.css('tr').drop(1) # Remove the header row
    AgendaUtils.log("#{__method__.to_s}() Parsing agenda html list table, children #{rows.length}")
    rows.each do |row|
      next if 'collapse' == row['class'] # Skip duplicate mobile-only rows, if any
      meeting = parse_meeting_item(row)
      meetings[meeting[AgendaUtils::ISODATE]] = meeting
    end
    return meetings
  end
  
  # Parse an meeting agenda listing html item row 
  # @param row of tr holding the item
  # @return hash of this agenda's links
  def parse_meeting_item(row)
    meeting = {}
    begin
      meeting[AgendaUtils::DATE] = row.css('td:nth-child(2)').text.strip
      meeting[AgendaUtils::ISODATE] = Date.strptime(meeting[AgendaUtils::DATE], "%m/%d/%y")
      meeting[AgendaUtils::TITLE] = row.css('td:nth-child(3) label').text.strip
      meeting[AgendaUtils::LOCATION] = row.css('td:nth-child(4)').text.strip
      a = row.css('td:nth-child(5) a')
      if a.any?
        meeting[AgendaUtils::VIEWURL] = a[0]['onclick'].split("'")[1]
      end
      a = row.css('td:nth-child(6) a')
      if a.any?
        meeting[AgendaUtils::PDFURL] = a[0]['href']
      end
      a = row.css('td:nth-child(7) a')
      if a.any?
        meeting[AgendaUtils::MINUTESURL] = a[0]['href']
      end
    rescue StandardError => e
      meeting[AgendaUtils::ERROR] = e.message
      meeting[AgendaUtils::STACK] = e.backtrace.join("\n\t")
    end
    return meeting
  end
  
  # Download various meeting agendas from a preparsed meeting agenda listing html (or use cached files)
  # @param type of agenda: SELECT_BOARD, ARB_BOARD, etc. (points to a parser)
  # @param dir to place files
  # @param json hash from parse_meeting_list() output
  # @return array of agenda detail hashes, annotated with filename; or with error
  # Side effect: creates local dir/2020-05-05-type.html files
  def download_meetings(type, dir, meetings)
    AgendaUtils.log("#{__method__.to_s}() Downloading meeting agendas of #{type} meetings #{meetings.length} into #{dir}")
    meetings.each do |isodate, meeting|
      meeting.has_key?(AgendaUtils::FILENAME) ? fn = File.join(dir, meeting[AgendaUtils::FILENAME]) : fn = File.join(dir, "#{isodate}-#{type}.html")
      if File.file?(fn)
        AgendaUtils.log("Found cached file #{fn}")
      else    
        AgendaUtils.log("Downloading file #{fn}")
        begin
          File.open(File.join(dir, "#{fn}"), "w") do |f|
            f.write(open(AgendaUtils::NOVUS_URL + meeting[AgendaUtils::VIEWURL]).read)
          end
          meeting[AgendaUtils::FILENAME] = fn
        rescue StandardError => e
          meeting[AgendaUtils::ERROR] = e.message
          meeting[AgendaUtils::STACK] = e.backtrace.join("\n\t")
        end
      end
    end
    return meetings
  end
  
  # Parse previously downloaded meeting agendas of specified type 
  # @param type of agenda: SELECT_BOARD, ARB_BOARD, etc. (points to a parser)
  # @param dir to scan for isodate-type.html files
  # @param io of the json details
  # @return hash of isodate => agenda detail hashes, annotated
  def parse_agendas(type, dir, meetings)
    hash = {}
    begin
      AgendaUtils.log("#{__method__.to_s}() Parsing #{type} agendas # #{meetings.length} from #{dir}")
      meetings.each do |isodate, meeting|
        # Annotate each item by parsing corresponding file
        meeting.has_key?(AgendaUtils::FILENAME) ? fn = File.join(dir, meeting[AgendaUtils::FILENAME]) : fn = File.join(dir, "#{isodate}-#{type}.html")
        if File.file?(fn)
          case type
          when AgendaUtils::SELECT
            meeting[AgendaUtils::AGENDA] = SelectParser.parse(File.open(fn), fn, meeting[AgendaUtils::ISODATE])
            AgendaUtils::add_video(AgendaUtils::SELECT, meeting[AgendaUtils::AGENDA])
          when AgendaUtils::ARB
            meeting[AgendaUtils::AGENDA] = ARBParser.parse(File.open(fn), fn, meeting[AgendaUtils::ISODATE])
            AgendaUtils::add_video(AgendaUtils::ARB, meeting[AgendaUtils::AGENDA])
          else
            meeting[AgendaUtils::ERROR] = "Unknown agenda type(#{type}) for: #{fn}"
          end
        else
          meeting[AgendaUtils::ERROR] = "File not found: #{fn}"
        end
        AgendaUtils::add_coversheets(meeting) if meeting[AgendaUtils::AGENDA].has_key?(AgendaUtils::ITEMS)
        hash[meeting[AgendaUtils::ISODATE]] = meeting 
      end
    rescue StandardError => e
      AgendaUtils.log(e.message)
      AgendaUtils.log(e.backtrace.join("\n\t"))
    end
    return hash
  end
  
  # ## ### #### ##### ######
  # Check commandline options
  def parse_commandline
    options = {}
    OptionParser.new do |opts|
      opts.on('-h', '--help', 'Print help for this program') { puts "#{DESCRIPTION}\n#{opts}"; exit }
      # Various inputs/outputs or options
      opts.on('-iINPUT', '--input INPUTFILE', 'Input filename to use for current operation') do |file|
        if File.file?(file)
          options[:file] = file
        elsif /http/ =~ file
          options[:url] = url
        else
          raise ArgumentError, "-a #{file} is neither a valid file nor an apparent URL" 
        end
      end
      opts.on('-oOUTFILE.JSON', '--out OUTFILE.JSON', 'Output filename to write parsed data (default: agenda.json)') do |out|
        options[:out] = out
      end
      opts.on('-dDIR', '--dir DIR', 'Working directory for downloaded files') do |dir|
        if File.directory?(dir)
          options[:dir] = dir
        else
          raise ArgumentError, "-d #{dir} is not a valid file" 
        end
      end
      opts.on('-tTYPE', '--type TYPE', 'Type of parsing to do: (select|arb|school,etc.)') do |type|
        options[:type] = type
      end

      # Various commands of what to do
      opts.on('-l', 'Read agenda meeting listing of HTML listing and output json list') do |mlist|
        options[:mlist] = true
      end
      opts.on('-x', 'Download agenda meeting listing and download to individual agendas linked therefrom') do |dld|
        options[:dld] = true
      end
      opts.on('-p', 'Parse downloaded agendas of a TYPE') do |parse|
        options[:parse] = true
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
    agenda = {}
    if options.has_key?(:mlist)
      puts "Parsing meeting list html #{ioname}"
      agenda = parse_meeting_list(io)
    elsif options.has_key?(:dld)
      puts "Downloading meeting files #{ioname} of type: #{options[:type]} into dir: #{options[:dir]}"
      agenda = download_meetings(options[:type], options[:dir], JSON.parse(io))
    elsif options.has_key?(:parse)
      puts "Parsing downloaded meeting files #{ioname} of type: #{options[:type]} from dir: #{options[:dir]}"
      agenda = parse_agendas(options[:type], options[:dir], JSON.parse(io))
    end

    puts "Outputting file #{options[:out]}"
    File.open("#{options[:out]}", "w") do |f|
      f.puts JSON.pretty_generate(agenda)
    end
  end
end
