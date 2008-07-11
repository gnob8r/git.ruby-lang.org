#!/usr/bin/env ruby

require "optparse"
require "ostruct"

SENDMAIL = "/usr/sbin/sendmail"

def parse(args)
  options = OpenStruct.new
  options.to = []
  options.error_to = []
  options.from = nil
  options.repository_uri = nil
  options.rss_path = nil
  options.rss_uri = nil
  options.name = nil
  options.viewvc_uri = nil

  opts = OptionParser.new do |opts|
    opts.separator ""

    opts.on("-I", "--include [PATH]",
            "Add [PATH] to load path") do |path|
      $LOAD_PATH.unshift(path)
    end

    opts.on("-t", "--to [TO]",
            "Add [TO] to to address") do |to|
      options.to << to unless to.nil?
    end

    opts.on("-e", "--error-to [TO]",
            "Add [TO] to to address when error is occurred") do |to|
      options.error_to << to unless to.nil?
    end

    opts.on("-f", "--from [FROM]",
            "Use [FROM] as from address") do |from|
      options.from = from
    end

    opts.on("--viewvc-uri [URI]",
            "Use [URI] as URI of viewvc") do |uri|
      options.viewvc_uri = uri
    end

    opts.on("-r", "--repository-uri [URI]",
            "Use [URI] as URI of repository") do |uri|
      options.repository_uri = uri
    end

    opts.on("--rss-path [PATH]",
            "Use [PATH] as output RSS path") do |path|
      options.rss_path = path
    end

    opts.on("--rss-uri [URI]",
            "Use [URI] as output RSS URI") do |uri|
      options.rss_uri = uri
    end

    opts.on("--name [NAME]",
            "Use [NAME] as repository name") do |name|
      options.name = name
    end

    opts.on_tail("--help", "Show this message") do
      puts opts
      exit
    end
  end

  opts.parse!(args)

  options
end

def make_body(info, params)
  body = ""
  body << "#{info.author}\t#{format_time(info.date)}\n"
  body << "\n"
  body << "  New Revision: #{info.revision}\n"
  body << "\n"
  body << change_info(info, params[:viewvc_uri])
  body << "\n"
  body << "  Log:\n"
  info.log.each_line do |line|
    body << "    #{line.sub(/^\t/,'')}".rstrip + "\n"
  end
  body << "\n"
  body << added_dirs(info)
  body << added_files(info)
  body << deleted_dirs(info)
  body << deleted_files(info)
  body << modified_dirs(info)
  body << modified_files(info)
  body.rstrip + "\n"
end

def format_time(time)
  time.strftime('%Y-%m-%d %X %z (%a, %d %b %Y)')
end

def changed_items(title, type, items)
  rv = ""
  unless items.empty?
    rv << "  #{title} #{type}:\n"
    rv << items.collect {|item| "    #{item}\n"}.join('')
  end
  rv
end

def changed_files(title, files)
  changed_items(title, "files", files)
end

def added_files(info)
  changed_files("Added", info.added_files)
end

def deleted_files(info)
  changed_files("Removed", info.deleted_files)
end

def modified_files(info)
  changed_files("Modified", info.updated_files)
end

def changed_dirs(title, files)
  changed_items(title, "directories", files)
end

def added_dirs(info)
  changed_dirs("Added", info.added_dirs)
end

def deleted_dirs(info)
  changed_dirs("Removed", info.deleted_dirs)
end

def modified_dirs(info)
  changed_dirs("Modified", info.updated_dirs)
end


CHANGED_TYPE = {
  :added => "Added",
  :modified => "Modified",
  :deleted => "Deleted",
  :copied => "Copied",
  :property_changed => "Property changed",
}

def change_info(info, uri)
  "  #{uri}?view=rev&revision=#{info.revision}\n"
end

def changed_dirs_info(info, uri)
  rev = info.revision
  (info.added_dirs.collect do |dir|
     "  Added: #{dir}\n"
   end + info.deleted_dirs.collect do |dir|
     "  Deleted: #{dir}\n"
   end + info.updated_dirs.collect do |dir|
     "  Modified: #{dir}\n"
   end).join("\n")
end

def diff_info(info, uri)
  info.diffs.collect do |key, values|
    [
      key,
      values.collect do |type, value|
        case type
        when :added
          command = "cat"
          rev = "?revision=#{info.revision}&view=markup"
        when :modified, :property_changed
          command = "diff"
          rev = "?r1=#{info.revision}&r2=#{info.revision - 1}&diff_format=u"
        when :deleted, :copied
          command = "cat"
          rev = ""
        else
          raise "unknown diff type: #{value[:type]}"
        end

        link = [uri, key.sub(/ .+/,"")||""].join("/") + rev

=begin without_diff
        desc = <<-HEADER
  #{CHANGED_TYPE[value[:type]]}: #{key} (+#{value[:added]} -#{value[:deleted]})
HEADER

#       result << <<-CONTENT
#     % svn #{command} -r #{rev} #{link}
# CONTENT

        desc << value[:body]
=end
        desc = ''

        [desc, link]
      end
    ]
  end
end

def make_header(to, from, info, params)
  headers = []
  headers << x_author(info)
  headers << x_repository(info)
  headers << x_revision(info)
  headers << x_id(info)
#  headers << x_sha256(info)
  headers << "Content-Type: text/plain; charset=us-ascii"
  headers << "Content-Transfer-Encoding: 7bit"
  headers << "From: #{from}"
  headers << "To: #{to.join(' ')}"
  headers << "Subject: #{make_subject(params[:name], info)}"
  headers.find_all do |header|
    /\A\s*\z/ !~ header
  end.join("\n")
end

def make_subject(name, info)
  branches = info.sha256.map{|x,| x[/(?:branches\/|tags\/)?(.+?)\//, 1]}.uniq
  subject = ""
  subject << "#{name}:" if name
  subject << "r#{info.revision}"
  subject << " (#{branches.join(', ')})" unless branches.empty?
  subject << ": "
  subject << info.log.to_a.first.to_s.strip
  subject
end

def x_author(info)
  "X-SVN-Author: #{info.author}"
end

def x_repository(info)
  # "X-SVN-Repository: #{info.path}"
  "X-SVN-Repository: XXX"
end

def x_id(info)
  "X-SVN-Commit-Id: #{info.entire_sha256}"
end

def x_revision(info)
  "X-SVN-Revision: #{info.revision}"
end

def x_sha256(info)
  info.sha256.collect do |name, inf|
    "X-SVN-SHA256-Info: #{name}, #{inf[:revision]}, #{inf[:sha256]}"
  end.join("\n")
end

def make_mail(to, from, info, params)
  make_header(to, from, info, params) + "\n" + make_body(info, params)
end

def sendmail(to, from, mail)
  open("| #{SENDMAIL} #{to.join(' ')}", "w") do |f|
    f.print(mail)
  end
end

def output_rss(name, file, rss_uri, repos_uri, info)
  prev_rss = nil
  begin
    if File.exist?(file)
      File.open(file) do |f|
        prev_rss = RSS::Parser.parse(f)
      end
    end
  rescue RSS::Error
  end

  File.open(file, "w") do |f|
    f.print(make_rss(prev_rss, name, rss_uri, repos_uri, info).to_s)
  end
end

def make_rss(base_rss, name, rss_uri, repos_uri, info)
  RSS::Maker.make("1.0") do |maker|
    maker.encoding = "UTF-8"

    maker.channel.about = rss_uri
    maker.channel.title = rss_title(name || repos_uri)
    maker.channel.link = repos_uri
    maker.channel.description = rss_title(name || repos_uri)
    maker.channel.dc_date = info.date

    if base_rss
      base_rss.items.each do |item|
        item.setup_maker(maker)
      end
    end

    diff_info(info, repos_uri).each do |name, infos|
      infos.each do |desc, link|
        item = maker.items.new_item
        item.title = name
        item.description = desc
        item.content_encoded = "<pre>#{h(desc)}</pre>"
        item.link = link
        item.dc_date = info.date
        item.dc_creator = info.author
      end
    end

    maker.items.do_sort = true
    maker.items.max_size = 15
  end
end

def rss_title(name)
  "Repository of #{name}"
end

def rss_items(items, info, repos_uri)
  diff_info(info, repos_uri).each do |name, infos|
    infos.each do |desc, link|
      items << [link, name, desc, info.date]
    end
  end

  items.sort_by do |uri, title, desc, date|
    date
  end.reverse
end

def main
  repos, revision, to, *rest = ARGV
  options = parse(rest)

  require "svn/info"
  info = Svn::Info.new(repos, revision)
  from = options.from || info.author + "@ruby-lang.org"
  to = [to, *options.to]
  params = {
    :repository_uri => options.repository_uri,
    :viewvc_uri => options.viewvc_uri,
    :name => options.name
  }
  sendmail(to, from, make_mail(to, from, info, params))

  if options.repository_uri and
      options.rss_path and
      options.rss_uri
    require "rss/1.0"
    require "rss/dublincore"
    require "rss/content"
    require "rss/maker"
    include RSS::Utils
    output_rss(options.name,
               options.rss_path,
               options.rss_uri,
               options.repository_uri,
               info)
  end
end

begin
  main
rescue Exception
  _, _, to, *rest = ARGV
  to = [to]
  from = ENV["USER"]
  begin
    options = parse(rest)
    to = options.error_to unless options.error_to.empty?
    from = options.from
  rescue Exception
  end
  sendmail(to, from, <<-MAIL)
From: #{from}
To: #{to.join(', ')}
Subject: Error

#{$!.class}: #{$!.message}
#{$@.join("\n")}
MAIL
end
