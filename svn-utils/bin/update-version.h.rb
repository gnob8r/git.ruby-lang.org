#!/usr/bin/env ruby
#
#$:.unshift File.join(File.dirname(__FILE__), "lib")
$:.unshift "/export/home/svn/scripts/svn-util/lib"
require "fileutils"
require "svn/info"

repos, revision = ARGV

info = Svn::Info.new repos, revision
branches = info.sha256.map{|x,| x[/(?:branches\/|tags\/)?(.+?)\//, 1]}.uniq
branches.each do |b|
  if info.diffs.map{|f,|f}.grep(/version\.h/).empty?
    Dir.chdir File.expand_path("~")
    FileUtils.rm_rf "work/version"
    FileUtils.mkdir_p "work/version/.svn/tmp"
    File.open("work/version/.svn/entries", "w") do |fh|
      fh.print "8\n\ndir\n1\nfile:///#{repos}/#{b}\nfile:///#{repos}\n\f\n"
    end
    Dir.chdir "work/version"
    system "svn cleanup; cp -rp .svn/tmp/* .svn; svn up version.h"
    formats = {
      'DATE' => [/"\d{4}-\d\d-\d\d"/, '"%Y-%m-%d"'],
      'TIME' => [/".+"/, '"%H:%M:%S"'],
      'CODE' => [/\d+/, '%Y%m%d'],
      'YEAR' => [/\d+/, '%Y'],
      'MONTH' => [/\d+/, '%m'],
      'DAY' => [/\d+/, '%d']
    }

    now = Time.now

    ARGV.replace ["version.h"]
    $-i = '~'

    while line = gets
      if /RUBY_RELEASE_(#{formats.keys.join('|')})/o =~ line
        format = formats[$1]
        line.sub!(format[0]) do
          now.strftime(format[1]).sub(/^0/, '')
        end
      end
      print line
    end
    system "svn commit -m #{now.strftime '%Y-%m-%d'} version.h"
    Dir.chdir ".."
    FileUtils.rm_rf "version"
  end
end
