quire 'pathname'
require 'pythonconfig'
require 'yaml'   # gereklilikleri belirliyoruz   # modul import ediyoruz

CONFiG = Config.fetch('presentation', {})   # ayarlar dosyasından presentation key ine karşılık gelen veriyi istiyorunz
# eğer yoksa boş sözlük vermesini söylüyoruz

PRESENTATiON_DiR = CONFiG.fetch('directory', 'p') # directory key ini istiyoruz #default değer 'p'
DEFAULT_CONFFiLE = CONFiG.fetch('conffile', '_templates/presentation.cfg') # coffile keyini istiyoruz #default değer '_templates/presentation.cfg'
iNDEX_FiLE = File.join(PRESENTATiON_DiR, 'index.html') # pythondaki open komutu gibi PRESENTATiON_DiR de bulunan index.hmtl dosyasını okuyoruz
iMAGE_GEOMETRY = [ 733, 550 ]  # bir arraya iki değer atıyoruz (bu değerleri sunumlardaki imajların azami boyutu olarak kullanacağız)
DEPEND_KEYS    = %w(source css js)  # 
DEPEND_ALWAYS  = %w(media)
TASKS = {
    :index   => 'sunumlari indeksle',
    :build   => 'sunumlari olustur',
    :clean   => 'sunumlari temizle',
    :view    => 'sunumlari goruntule',
    :run     => 'sunumlari sun',
    :optim   => 'resimleri iyilestir',
    :default => 'ontanimli gorev',
}

presentation   = {}
tag            = {}

class File
  @@absolute_path_here = Pathname.new(Pathname.pwd)
  def self.to_herepath(path)
    Pathname.new(File.expand_path(path)).relative_path_from(@@absolute_path_here).to_s
  end
  def self.to_filelist(path)
    File.directory?(path) ?
      FileList[File.join(path, '*')].select { |f| File.file?(f) } :
      [path]
  end
end

def png_comment(file, string)
  require 'chunky_png'
  require 'oily_png'

  image = ChunkyPNG::image.from_file(file)
  image.metadata['Comment'] = 'raked'
  image.save(file)
end

def png_optim(file, threshold=40000)
  return if File.new(file).size < threshold
  sh "pngnq -f -e .png-nq #{file}"
  out = "#{file}-nq"
  if File.exist?(out)
    $?.success? ? File.rename(out, file) : File.delete(out)
  end
  png_comment(file, 'raked')
end

def jpg_optim(file)
  sh "jpegoptim -q -m80 #{file}"
  sh "mogrify -comment 'raked' #{file}"
end

def optim
  pngs, jpgs = FileList["**/*.png"], FileList["**/*.jpg", "**/*.jpeg"]

  [pngs, jpgs].each do |a|
    a.reject! { |f| %x{identify -format '%c' #{f}} =~ /[Rr]aked/ }
  end

  (pngs + jpgs).each do |f|
    w, h = %x{identify -format '%[fx:w] %[fx:h]' #{f}}.split.map { |e| e.to_i }
    size, i = [w, h].each_with_index.max
    if size > iMAGE_GEOMETRY[i]
      arg = (i > 0 ? 'x' : '') + iMAGE_GEOMETRY[i].to_s
      sh "mogrify -resize #{arg} #{f}"
    end
  end

  pngs.each { |f| png_optim(f) }
  jpgs.each { |f| jpg_optim(f) }

  (pngs + jpgs).each do |f|
    name = File.basename f
    FileList["*/*.md"].each do |src|
      sh "grep -q '(.*#{name})' #{src} && touch #{src}"
    end
  end
end

default_conffile = File.expand_path(DEFAULT_CONFFiLE)

FileList[File.join(PRESENTATiON_DiR, "[^_.]*")].each do |dir|
  next unless File.directory?(dir)
  chdir dir do
    name = File.basename(dir)
    conffile = File.exists?('presentation.cfg') ? 'presentation.cfg' : default_conffile
    config = File.open(conffile, "r") do |f|
      PythonConfig::ConfigParser.new(f)
    end

    landslide = config['landslide']
    if ! landslide
      $stderr.puts "#{dir}: 'landslide' bolumu tanimlanmamis"
      exit 1
    end

    if landslide['destination']
      $stderr.puts "#{dir}: 'destination' ayari kullanilmis; hedef dosya belirtilmeyin"
      exit 1
    end

    if File.exists?('index.md')
      base = 'index'
      ispublic = true
    elsif File.exists?('presentation.md')
      base = 'presentation'
      ispublic = false
    else
      $stderr.puts "#{dir}: sunum kaynagi 'presentation.md' veya 'index.md' olmali"
      exit 1
    end

    basename = base + '.html'
    thumbnail = File.to_herepath(base + '.png')
    target = File.to_herepath(basename)

    deps = []
    (DEPEND_ALWAYS + landslide.values_at(*DEPEND_KEYS)).compact.each do |v|
      deps += v.split.select { |p| File.exists?(p) }.map { |p| File.to_filelist(p) }.flatten
    end

    deps.map! { |e| File.to_herepath(e) }
    deps.delete(target)
    deps.delete(thumbnail)

    tags = []

   presentation[dir] = {
      :basename  => basename, # uretecegimiz sunum dosyasinin baz adi
      :conffile  => conffile, # landslide konfigurasyonu (mutlak dosya yolu)
      :deps      => deps, # sunum bagimliliklari
      :directory => dir,  # sunum dizini (tepe dizine goreli)
      :name      => name, # sunum ismi
      :public    => ispublic, # sunum disari acik mi
      :tags      => tags, # sunum etiketleri
      :target    => target, # uretecegimiz sunum dosyasi (tepe dizine goreli)
      :thumbnail => thumbnail,  # sunum icin kucuk resim
    }
  end
end

presentation.each do |k, v|
  v[:tags].each do |t|
    tag[t] ||= []
    tag[t] << k
  end
end

tasktab = Hash[*TASKS.map { |k, v| [k, { :desc => v, :tasks => [] }] }.flatten]

presentation.each do |presentation, data|
  ns = namespace presentation do
    file data[:target] => data[:deps] do |t|
      chdir presentation do
        sh "landslide -i #{data[:conffile]}"
        sh 'sed -i -e "s/^\([[:blank:]]*var hiddenContext = \)false\(;[[:blank:]]*$\)/\1true\2/" presentation.html'
        unless data[:basename] == 'presentation.html'
          mv 'presentation.html', data[:basename]
        end
      end
    end

    file data[:thumbnail] => data[:target] do
      next unless data[:public]
      sh "cutycapt " +
          "--url=file://#{File.absolute_path(data[:target])}#slide1 " +
          "--out=#{data[:thumbnail]} " +
          "--user-style-string='div.slides { width: 900px; overflow: hidden; }' " +
          "--min-width=1024 " +
          "--min-height=768 " +
          "--delay=1000"
      sh "mogrify -resize 240 #{data[:thumbnail]}"
      png_optim(data[:thumbnail])
    end

    task :optim do
      chdir presentation do
        optim
      end
    end

    task :index => data[:thumbnail]

    task :build => [:optim, data[:target], :index]

    task :view do
      if File.exists?(data[:target])
        sh "touch #{data[:directory]}; #{browse_command data[:target]}"
      else
        $stderr.puts "#{data[:target]} bulunamadi; once insa edin"
      end
    end

    task :run => [:build, :view]

    task :clean do
      rm_f data[:target]
      rm_f data[:thumbnail]
    end

    task :default => :build
  end

  ns.tasks.map(&:to_s).each do |t|
    _, _, name = t.partition(":").map(&:to_sym)
    next unless tasktab[name]
    tasktab[name][:tasks] << t
  end
end

namespace :p do
  tasktab.each do |name, info|
    desc info[:desc]
    task name => info[:tasks]
    task name[0] => name
  end

  task :build do
    index = YAML.load_file(iNDEX_FiLE) || {}
    presentations = presentation.values.select { |v| v[:public] }.map { |v| v[:directory] }.sort
    unless index and presentations == index['presentations']
      index['presentations'] = presentations
      File.open(iNDEX_FiLE, 'w') do |f|
        f.write(index.to_yaml)
        f.write("---\n")
      end
    end
  end

  desc "sunum menusu"
  task :menu do
    lookup = Hash[
      *presentation.sort_by do |k, v|
        File.mtime(v[:directory])
      end
      .reverse
      .map { |k, v| [v[:name], k] }
      .flatten
    ]
    name = choose do |menu|
      menu.default = "1"
      menu.prompt = color(
        'Lutfen sunum secin ', :headline
      ) + '[' + color("#{menu.default}", :special) + ']'
      menu.choices(*lookup.keys)
    end
    directory = lookup[name]
    Rake::Task["#{directory}:run"].invoke
  end
  task :m => :menu
end

desc "sunum menusu"
task :p => ["p:menu"]
task :presentation => :p

