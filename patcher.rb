# Author           : Dominik Kinal ( kinaldominik@gmail.com )
# Created On       : 06.04.2016
# Last Modified By : Dominik Kinal ( kinaldominik@gmail.com )
# Last Modified On : 06.04.2016
# Version          : 1.0
#
# Description      :
# Creates "binary file differences" patches of every file in whole directory.
# Patch file contains data about all differences between "old" and "new" file.
# Patch files are saved in RFC 3284 (VCDIFF) format. (http://www.rfc-base.org/rfc-3284.html)
# Uses Xdelta3 (apt-get install xdelta3) to create patch, Tar and Gzip to compression.
#
# Process:
# 1) Directory structure of "SourceNew" is copied to "tmp" and is filled with all new files. ("New" file is that file which is in "SourceNew" but not in "SourceOld").
# 2) Then "tmp" directory is compressed to "newfiles.tgz" and removed.
# 3) For every file (if it is not "new") in "SourceNew" directory, program creates patch between this file (in "SourceNew") and the one in "SourceOld" and saves it (.patch file) to "out" directory.
# 4) Finally, creates a List file containing all patch files.
#
#
# Options:
# -h		        	Help
# -v			        Version and Credits
# -c              Specify Config file
# -x 			        Creates also List file (mentioned in Process point 4)
# -o <directory>	Specify a "SourceOld" directory
# -n <directory>	Specify a "SourceNew" directory
# -t <directory>	Specify a "out" directory
# -z <name>		    Specify a .tgz file name (mentioned in Process point 2)
# -l			        Creates only a List file (mentioned in Process point 4)
# -g [0-9]		    Changes compression of gzip (0-9 level of compression: 0-none, 9-best)
# -p <version>    Packs all output files and specify its version code
#
# Default options are located in config.yaml
#
#
# Licensed under GPL (see /usr/share/common-licenses/GPL for more details
# or contact # the Free Software Foundation for a copy)
#
# Xdelta3 Licence:
# Xdelta3 is covered under the terms of the GPL, see COPYING (https://github.com/jmacd/xdelta/blob/release3_1/xdelta3/COPYING).


require 'yaml'
require 'optparse'
require 'fileutils'
require 'rubygems'
require 'rubygems/package'
require 'zlib'

# noinspection RubyStringKeysInHashInspection
$options = {
    'configFile' => 'config.yaml',
    'directories' => {
        'out' => 'out/',
        'new' => 'new/',
        'old' => 'old/'
    },
    'gzipCompression' => 6,
    'tarFileName' => 'newFiles',
    'createListFile' => false,
    'createOnlyListFile' => false,
    'pack' => false
}

def load_config
  if File.exist?($options['configFile']) and YAML::load_file($options['configFile'])
    YAML::load_file($options['configFile']).each do |key, value|
      if value.is_a?(Hash)
        value.each do |k, v|
          $options[key][k] = v
        end
      else
        $options[key] = value
      end
    end
  else
    puts 'No config file found. Creating...'
    File.open($options['configFile'], 'w') {|f| f.write $options.to_yaml }
  end
end

load_config

OptionParser.new do |opts|
  opts.banner = 'Usage: patcher.rb [options]'

  opts.on('-c file', '--config file', 'Load custom config file') do |file|
    if File.exist?(file)
      $options['configFile'] = file
      load_config
    else
      puts 'Could not find given config file'
    end
  end

  opts.on('-t directory', '--out directory', 'Specify Output directory') do |directory|
    directory << '/' unless directory.end_with?('/')
    $options['directories']['out'] = directory
  end

  opts.on('-o directory', '--old directory', 'Specify oldDirectory') do |directory|
    directory << '/' unless directory.end_with?('/')
    $options['directories']['old'] = directory
  end

  opts.on('-n directory', '--new directory', 'Specify newDirectory') do |directory|
    directory << '/' unless directory.end_with?('/')
    $options['directories']['new'] = directory
  end

  opts.on('-z file', '--zip file', 'Specify name of new files zip package') do |file|
    $options['tarFileName'] = file
  end

  opts.on('-g level', '--gzip level', 'Set Gzip compression level (0-9)') do |level|
    level = level.to_i
    $options['gzipCompression'] = level if level.is_a? Integer and level >= 0 and level <= 9
  end

  opts.on('-x', '--[no-]list', 'Create also a List file (--no-list to not create)') do |v|
    $options['createListFile'] = v
  end

  opts.on('-l', '--onlyList', 'Create only a List file') do |v|
    $options['createOnlyListFile'] = v
  end

  opts.on('-p version', '--pack version', 'Packs all output files and specify its version code') do |version|
    $options['pack'] = version if version =~ /[0-9]+\.[0-9]+/
  end

  opts.on('-v', '--version', 'Version and credits') do
    puts 'Patcher\nAutor: Dominik Kinal\nWersja: 1.0\nLicencja: GPL'
  end

  opts.on('-h', '--help', 'Help') do
    puts opts
    exit
  end
end.parse!

def tar(path)
  tar_file = StringIO.new
  Gem::Package::TarWriter.new(tar_file) do |tar|
    Dir[File.join(path, '**/*')].each do |file|
      mode = File.stat(file).mode
      relative_file = file.sub /^#{Regexp::escape path}\/?/, ''

      if File.directory?(file)
        tar.mkdir relative_file, mode
      else
        tar.add_file relative_file, mode do |tf|
          File.open(file, 'rb') do |f|
            tf.write f.read
          end
        end
      end
    end
  end

  tar_file.rewind
  tar_file
end

def gzip(tar_file)
  gz = StringIO.new
  level = $options['gzipCompression']
  level = 6 if level < 0 or level > 9
  p level

  z = Zlib::GzipWriter.new(gz, level)
  z.write tar_file.string
  z.close

  StringIO.new gz.string
end

def tar_gz(filename, path)
  io = tar path
  gz = gzip io
  File.open(filename, 'wb') do |f|
    f.write gz.read
  end
end

def create_patch(old_file, new_file, output_file)

  command = %w(xdelta3.exe -f)
  command += ['-e']
  command += ['-s', old_file] if File.file? old_file
  command += [new_file, output_file]

  is_success = system *command

  raise "Could not create delta with command \"#{command.join(' ')}\"" unless is_success
end


## Check for directories existence - if not, create them
unless Dir.exist?($options['directories']['old'])
  Dir.mkdir $options['directories']['old']
  p 'Old directory not Found! Creating...'
end

unless Dir.exist?($options['directories']['new'])
  Dir.mkdir $options['directories']['new']
  p 'New directory not Found! Creating...'
end

def clean_out_dir
  ## Clean Out directory
  FileUtils.rm_rf("#{$options['directories']['out']}/.", secure: true)
  Dir.mkdir($options['directories']['out']) unless Dir.exist?($options['directories']['out'])

end

unless $options['createOnlyListFile']
  clean_out_dir

  ## Clean Tmp directory
  FileUtils.rm_rf('tmp/.', secure: true)
  Dir.mkdir 'tmp/' unless Dir.exist?('tmp/')


  ## Recreate directory structure from new to tmp (Process no 1)
  Dir.glob("#{$options['directories']['new']}/**/*").each do |f|
    if File.directory?(f)
      f = f.sub /^#{$options['directories']['new']}\//, ''
      #puts "#{f}\n"
      FileUtils.mkpath 'tmp/' + f
    end
  end
end

if $options['createListFile']
  patched_files = Hash.new

  if $options['pack']
    patched_files['version'] = $options['pack']
  end

  patched_files['updated'] = Array.new
  patched_files['new'] = Array.new
  patched_files['removed_directories'] = Array.new
  patched_files['removed_files'] = Array.new
end

## Check files
Dir.glob("#{$options['directories']['new']}/**/*").each do |f|
  if File.file?(f)
    f = f.sub /^#{$options['directories']['new']}\//, ''
    #puts "#{f}\n"
    if File.exist?($options['directories']['old'] + f) # If it exist in old - make delta file (Process no 3)
      unless FileUtils.identical?($options['directories']['old'] + f, $options['directories']['new'] + f)
        unless $options['createOnlyListFile']
          create_patch $options['directories']['old'] + f, $options['directories']['new'] + f, $options['directories']['out'] + f + '.upd'
        end

        if $options['createListFile']
          patched_files['updated'].push f
        end
      end
    else #If its not - copy file to tmp (Process no 1)
      unless $options['createOnlyListFile']
        FileUtils.cp $options['directories']['new'] + f, 'tmp/' + f
      end

      if $options['createListFile']
        patched_files['new'].push f
      end
    end
  end
end

## Look for removed files and directories
if $options['createListFile']
  Dir.glob("#{$options['directories']['old']}/**/*").each do |f|
    f = f.sub /^#{$options['directories']['old']}\//, ''
    if File.file?("#{$options['directories']['old']}/" + f) and not File.exist?($options['directories']['new'] + f)
      patched_files['removed_files'].push f
    elsif File.directory?("#{$options['directories']['old']}/" + f) and not Dir.exist?($options['directories']['new'] + f)
      patched_files['removed_directories'].push f
    end
  end

  File.open('patchedFiles.yaml', 'w') do |f|
    f.write patched_files.to_yaml
  end
end

## Compress tmp directory and remove it (Process no 2)
unless $options['createOnlyListFile']
  tar_gz $options['tarFileName'] + '.tar.gz', 'tmp/'
  FileUtils.rm_r 'tmp/' if Dir.exist?('tmp/')
end

if $options['pack']
  dir_name = 'p' + $options['pack'].gsub(/\./, '-')
  if Dir.exist? dir_name
    FileUtils.rm_rf(dir_name, secure:true)
  end
  Dir.mkdir(dir_name)

  if $options['createListFile']
    FileUtils.copy 'patchedFiles.yaml', dir_name + '/'

    FileUtils.remove 'patchedFiles.yaml'
  end

  unless $options['createOnlyListFile']
    FileUtils.copy_entry $options['directories']['out'], dir_name + '/files/'
    FileUtils.copy $options['tarFileName'] + '.tar.gz', dir_name

    clean_out_dir
    FileUtils.remove $options['tarFileName'] + '.tar.gz'
  end
end
