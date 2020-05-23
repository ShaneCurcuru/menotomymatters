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
  (See AgendaUtils)
  
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
  require_relative 'schoolparser'
    
  # Download and parse any new meeting agendas from website (or use cached files)
  # @param type of agenda: SELECT_BOARD, ARB_BOARD, etc. (points to a parser)
  # @param dir to place files
  # @param meetings hash of existing meetings to add to
  # @return hash of all meetings available (both existing and newly parsed)
  # Side effect: creates local dir/2020-05-05-type.html files
  def process_latest(type, dir, meetings)
    raise ArgumentError, "No type #{type} of meeting to download provided" if type.nil? || type.empty?
    puts "WARNING: No working directory #{dir} provided, using ." unless dir
    AgendaUtils.log("#{__method__.to_s}() Processing all new meeting agendas of #{type} into #{dir}, adding to existing #{meetings.length}")
    # Find list of new agendas of this type
    hash = AgendaUtils.parse_meeting_list(open(AgendaUtils::DOWNLOAD_URLS[type]))
    # Merge new MINUTESURL into existing entries, and copy all over
    meetings.each do |isodate, mtg|
      if hash.has_key?(isodate)
        # Add any newly found MINUTESURL into existing meetings
        if hash[isodate].has_key?(AgendaUtils::MINUTESURL)
          mtg[AgendaUtils::MINUTESURL] = hash[isodate][AgendaUtils::MINUTESURL]
        end
        hash[isodate].merge!(mtg)
      else
        hash[isodate] = mtg
      end
    end
    # Download meetings or find cached files for all
    hash = AgendaUtils.download_meetings(type, dir, hash)
    # Process all agendas where needed
    hash = parse_agendas(type, dir, hash)
    return hash
  end
  
  # Parse previously downloaded meeting agendas of specified type when needed
  #   Only parses when needed; if data already exists in meetings input, skip re-parsing or processing
  # @param type of agenda: SELECT_BOARD, ARB_BOARD, etc. (points to a parser)
  # @param dir to scan for isodate-type.html files
  # @param meetings json of the agendas; either preparsed or just notice listings
  # @return hash of isodate => agenda detail hashes, annotated
  def parse_agendas(type, dir, meetings)
    hash = {}
    begin
      AgendaUtils.log("#{__method__.to_s}() Parsing #{type} agendas # #{meetings.length} from #{dir}")
      meetings.each do |isodate, meeting|
        # Don't re-parse previously processed meetings
        unless meeting.has_key?(AgendaUtils::AGENDA)
          # Annotate each item by parsing corresponding file
          meeting.has_key?(AgendaUtils::FILENAME) ? fn = meeting[AgendaUtils::FILENAME] : fn = File.join(dir, "#{isodate}-#{type}.html")
          if File.file?(fn)
            meeting[AgendaUtils::AGENDA] = parse_agenda(type, File.open(fn), fn, isodate)
            if meeting[AgendaUtils::AGENDA].has_key?(AgendaUtils::ITEMS)
 ### DEBUG             AgendaUtils::add_coversheets(meeting) 
 ### DEBUG             AgendaUtils::add_video(type, meeting)
            end
          else
            meeting[AgendaUtils::ERROR] = "File not found: #{fn}"
          end
        end
        # Always add this meeting to our return, even if we didn't re-parse
        hash[meeting[AgendaUtils::ISODATE]] = meeting 
      end
    rescue StandardError => e
      AgendaUtils.log(e.message)
      AgendaUtils.log(e.backtrace.join("\n\t"))
    end
    return hash
  end
  
  # Parse a single agendas of specified type from file or url 
  # @param type of agenda: SELECT_BOARD, ARB_BOARD, etc. (points to a parser)
  # @param input stream to read
  # @param ioname of input stream (for error reporting, etc.)
  # @param mdydate date string for video indexing
  # @return hash of isodate => agenda detail hashes, annotated
  def parse_agenda(type, input, ioname, isodate)
    agenda = {}
    begin
      AgendaUtils.log("#{__method__.to_s}() Parsing #{type} agenda from #{ioname}")
      case type
      when AgendaUtils::SELECT
        agenda = SelectParser.parse(input, ioname, isodate)
      when AgendaUtils::ARB
        agenda = ARBParser.parse(input, ioname, isodate)
      when AgendaUtils::SCHOOL
        agenda = SchoolParser.parse(input, ioname, isodate)
      else
        meeting[AgendaUtils::ERROR] = "Unknown agenda type(#{type}) for: #{ioname}"
      end
    rescue StandardError => e
      AgendaUtils.log(e.message)
      AgendaUtils.log(e.backtrace.join("\n\t"))
    end
    return agenda
  end
  
  # ## ### #### ##### ######
  # Check commandline options
  def parse_commandline
    options = {}
    OptionParser.new do |opts|
      opts.on('-h', '--help', 'Print help for this program') { puts "#{DESCRIPTION}\n#{opts}"; exit }
      # Various inputs/outputs or options
      opts.on('-iINPUT', '--input INPUTFILE', 'Input filename  or http... url to use for current operation') do |input|
        if File.file?(input)
          options[:ioname] = input
          options[:input] = File.read(options[:ioname])
        elsif /http/ =~ input
          options[:ioname] = input
          options[:input] = open(options[:ioname])
        else
          raise ArgumentError, "-a #{input} is neither a valid file nor an apparent URL" 
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
      opts.on('-cCROSSINDEX', '--crossindex CROSSINDEX.JSON', 'For ARB agendas, crossindex file to update') do |cindex|
        if File.file?(cindex)
          options[:cindex] = cindex
        else
          raise ArgumentError, "-a #{cindex} is not a valid file" 
        end
      end
      
      # Various commands of what to do
      opts.on('-n', 'Download and parse any new agendas of a TYPE') do |dldnew|
        options[:dldnew] = true
      end
      opts.on('-l', 'Read agenda meeting listing of HTML listing and output json list') do |mlist|
        options[:mlist] = true
      end
      opts.on('-x', 'Download agenda meeting listing and download to individual agendas linked therefrom') do |dld|
        options[:dld] = true
      end
      opts.on('-p', 'Parse downloaded list of agendas of a TYPE') do |parse|
        options[:parse] = true
      end
      opts.on('-s', 'Parse single agenda of a TYPE into single output') do |single|
        options[:single] = true
      end
      opts.on('-eISODATE', 'ISO formatted date for -s single agenda') do |isodate|
        options[:isodate] = isodate
      end
      
      begin
        opts.parse!
        raise ArgumentError, "No -i input file or url provided!" unless options.has_key?(:input)
        if options.has_key?(:dld) or options.has_key?(:parse)
          puts "WARNING: No apparent -d working directory when download/parsing requested, may crash"
        end    
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
    options[:out] ||= 'agendas.json'
    options[:dir] ||= '_agendas'
    options[:cindex] ||= '_data/meetings-arb-index.json'
    agenda = {}
    if options.has_key?(:dldnew)
      puts "Downloading and parsing any new agendas of #{options[:type]} in dir #{options[:dir]}"
      agenda = process_latest(options[:type], options[:dir], JSON.parse(options[:input]))
      if AgendaUtils::ARB.eql?(options[:type])
        # Also crossindex the data
        crossindex = ARBParser.post_process(agenda, options[:cindex])
        File.open("#{options[:cindex]}", "w") do |f|
          f.puts JSON.pretty_generate(crossindex)
        end
      end
    elsif options.has_key?(:mlist)
      puts "Parsing meeting list html #{options[:ioname]}"
      agenda = AgendaUtils.parse_meeting_list(options[:input])
    elsif options.has_key?(:dld)
      puts "Downloading meeting files #{options[:ioname]} of type: #{options[:type]} into dir: #{options[:dir]}"
      agenda = AgendaUtils.download_meetings(options[:type], options[:dir], JSON.parse(options[:input]))
    elsif options.has_key?(:parse)
      puts "Parsing downloaded meeting files #{options[:ioname]} of type: #{options[:type]} from dir: #{options[:dir]}"
      agenda = parse_agendas(options[:type], options[:dir], JSON.parse(options[:input]))
    elsif options.has_key?(:single)
      puts "Parsing single agenda #{options[:ioname]} of type: #{options[:type]} of #{options[:isodate]}"
      agenda = parse_agenda(options[:type], options[:input], options[:ioname], options[:isodate])
    end
    
    puts "Outputting file #{options[:out]}, sorted"
    File.open("#{options[:out]}", "w") do |f|
      f.puts JSON.pretty_generate(agenda.sort.reverse.to_h)
    end
  end
end
