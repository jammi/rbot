#-- vim:sw=2:et
#++
#
# :title: DICT (RFC 2229) Protocol Client Plugin for rbot
#
# Author:: Yaohan Chen <yaohan.chen@gmail.com>
# Copyright:: (C) 2007 Yaohan Chen
# License:: GPL v2
#
# Looks up words on a DICT server. DEFINE and MATCH commands, as well as listing of
# databases and strategies are supported.
#
# TODO
# Improve output format


# requires Ruby/DICT <http://www.caliban.org/ruby/ruby-dict.shtml>
require 'dict'

class ::String
  # Returns a new string truncated to length 'to'
  # If ellipsis is not given, that will just be the first n characters,
  # Else it will return a string in the form <head><ellipsis><tail>
  # The total length of that string will not exceed 'to'.
  # If tail is an Integer, the tail will be exactly 'tail' characters,
  # if it is a Float/Rational tails length will be (to*tail).ceil.
  #
  # Contributed by apeiros
  def truncate(to=32, ellipsis='…', tail=0.3)
    str  = split(//)
    return str.first(to).join('') if !ellipsis or str.length <= to
    to  -= ellipsis.split(//).length
    tail = (tail*to).ceil unless Integer === tail
    to  -= tail
    "#{str.first(to)}#{ellipsis}#{str.last(tail)}"
  end
end

class ::Definition
  def headword
    definition[0].strip
  end

  def body
    definition[1..-1].join.gsub(/\s+/, ' ').strip
  end
end

class DictClientPlugin < Plugin
  BotConfig.register BotConfigStringValue.new('dictclient.server',
    :default => 'dict.org',
    :desc => 'Hostname or hostname:port of the DICT server used to lookup words')
  BotConfig.register BotConfigIntegerValue.new('dictclient.max_defs_before_collapse',
    :default => 4,
    :desc => 'When multiple databases reply a number of definitions that above this limit, only the database names will be listed. Otherwise, the full definitions from each database are replied')
  BotConfig.register BotConfigIntegerValue.new('dictclient.max_length_per_def',
    :default => 200,
    :desc => 'Each definition is truncated to this length') 
  BotConfig.register BotConfigStringValue.new('dictclient.headword_format',
    :default => "#{Bold}<headword>#{Bold}",
    :desc => 'Format of headwords; <word> will be replaced with the actual word')
  BotConfig.register BotConfigStringValue.new('dictclient.database_format',
    :default => "#{Underline}<database>#{Underline}",
    :desc => 'Format of database names; <database> will be replaced with the database name')
  BotConfig.register BotConfigStringValue.new('dictclient.definition_format',
    :default => '<headword>: <definition> -<database>',
    :desc => 'Format of definitions. <word> will be replaced with the formatted headword, <def> will be replaced with the truncated definition, and <database> with the formatted database name')
  BotConfig.register BotConfigStringValue.new('dictclient.match_format',
    :default => '<matches>––<database>',
    :desc => 'Format of match results. <matches> will be replaced with the formatted headwords, <database> with the formatted database name')
  
  def initialize
    super
  end
  
  # create a DICT object, which is passed to the block. after the block finishes,
  # the DICT object is automatically disconnected. the return value of the block
  # is returned from this method.
  # if an IRC message argument is passed, the error message will be replied
  def with_dict(m=nil &block)
    server, port = @bot.config['dictclient.server'].split ':' if @bot.config['dictclient.server']
    server ||= 'dict.org'
    port ||= DICT::DEFAULT_PORT
    ret = nil
    begin
      dict = DICT.new(server, port)
      ret = yield dict
      dict.disconnect
    rescue ConnectError
      m.reply 'An error occured connecting to the DICT server. Check the dictclient.server configuration or retry later' if m
    rescue ProtocolError
      m.reply 'A protocol error occured' if m
    rescue DICTError
      m.reply 'An error occured' if m
    end
    ret
  end
  
  def format_headword(w)
    @bot.config['dictclient.headword_format'].gsub '<headword>', w
  end
    
  def format_database(d)
    @bot.config['dictclient.database_format'].gsub '<database>', d
  end
  
  def cmd_define(m, params)
    phrase = params[:phrase].to_s
    results = with_dict(m) {|d| d.define(params[:database], params[:phrase])}
    m.reply(
      if results
        # only list database headers if definitions come from different databases and
        # the number of definitions is above dictclient.max_defs_before_collapse
        if results.any? {|r| r.database != results[0].database} &&
           results.length > @bot.config['dictclient.max_defs_before_collapse']
          "Definitions for #{format_headword phrase} were found in #{
            results.collect {|r| r.database}.uniq.collect {|d|
              format_database d}.join ', '
          }. Specify database to view full result."
        # otherwise display the definitions
        else
          results.collect {|r|
            @bot.config['dictclient.definition_format'].gsub(
              '<headword>', format_headword(r.headword)
            ).gsub(
              '<database>', format_database(r.database)
            ).gsub(
              '<definition>', r.body.truncate(@bot.config['dictclient.max_length_per_def'])
            )
          }.join ' '
        end
      else
        "No definition for #{format_headword phrase} found from #{
          format_database params[:database]}."
      end
    )
  end
  
  def cmd_match(m, params)
    phrase = params[:phrase].to_s
    results = with_dict(m) {|d| d.match(params[:database],
                                        params[:strategy], phrase)}
    m.reply(
      if results
        results.collect {|database, matches|
          @bot.config['dictclient.match_format'].gsub(
            '<matches>', matches.collect {|m| format_headword m}.join(', ')
          ).gsub(
            '<database>', format_database(database)
          )
        }.join ' '
      else
        "Nothing matched for #{format_headword phrase
        } from #{format_database params[:database]} using #{params[:strategy]}"
      end
    )
  end
    
  def cmd_databases(m, params)
    with_dict(m) do |d|
      m.reply "Databases: #{
        d.show_db.collect {|db, d|"#{format_database db}: #{d}"}.join '; '
      }"
    end
  end
  
  def cmd_strategies(m, params)
    with_dict(m) do |d|
      m.reply "Strategies: #{
        d.show_strat.collect {|s, d| "#{s}: #{d}"}.join '; '
      }"
    end
  end
    
  def help(plugin, topic='')
    "define <phrase> [from <database>] => Show definition of a phrase; match <phrase> [using <strategy>] [from <database>] => Show matching phrases; dictclient databases => List databases; dictclient strategies => List strategies"
  end
end

plugin = DictClientPlugin.new

plugin.map 'define *phrase [from :database]',
           :action => 'cmd_define',
           :defaults => {:database => DICT::ALL_DATABASES}

plugin.map 'match *phrase [using :strategy] [from :database]',
           :action => 'cmd_match',
           :defaults => {:database => DICT::ALL_DATABASES,
                         :strategy => DICT::DEFAULT_MATCH_STRATEGY }

plugin.map 'dictclient databases', :action => 'cmd_databases'
plugin.map 'dictclient strategies', :action => 'cmd_strategies'