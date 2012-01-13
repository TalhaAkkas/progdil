quire 'pathname'
require 'pythonconfig'
require 'yaml'   # gereklilikleri belirliyoruz   # modul import ediyoruz

CONFiG = Config.fetch('presentation', {})   # ayarlar dosyasından presentation key ine karşılık gelen veriyi istiyorunz
# eğer yoksa boş sözlük vermesini söylüyoruz

PRESENTATiON_DiR = CONFiG.fetch('directory', 'p') # directory key ini istiyoruz #default değer 'p'
DEFAULT_CONFFiLE = CONFiG.fetch('conffile', '_templates/presentation.cfg') # coffile keyini istiyoruz #default değer '_templates/presentation.cfg'
iNDEX_FiLE = File.join(PRESENTATiON_DiR, 'index.html') # pythondaki open komutu gibi PRESENTATiON_DiR de bulunan index.hmtl dosyasını okuyoruz
iMAGE_GEOMETRY = [ 733, 550 ]  # bir arraya iki değer atıyoruz (bu değerleri sunumlardaki imajların azami boyutu olarak kullanacağız)
DEPEND_KEYS    = %w(source css js)  # bağımlılıklar içinde daima olacak anahtar kelimeleri belirledik
DEPEND_ALWAYS  = %w(media)  #bağımlılıkları için daima olabilecek klasorleri belirledik
TASKS = {
    :index   => 'sunumlari indeksle',
    :build   => 'sunumlari olustur',
    :clean   => 'sunumlari temizle',
    :view    => 'sunumlari goruntule',
    :run     => 'sunumlari sun',
    :optim   => 'resimleri iyilestir',
    :default => 'ontanimli gorev',
} # bir sözluk tanımladık  bunları tasklar la ilgili bilgi vermek için kullanacağız

presentation   = {} 
tag            = {} #presentation ve tag sözlüklerini ilkledik

class File  # File class ına monkey patch yontemi ile eklemelerde bulunuyoruz
  @@absolute_path_here = Pathname.new(Pathname.pwd) # static absolute_path_here değiskenini tanımladık ve su anki pwd ile ilkledik
  def self.to_herepath(path) # static erisimli bi metod  tanımladık
    Pathname.new(File.expand_path(path)).relative_path_from(@@absolute_path_here).to_s
  end# verdiğimiz  mutlak yolları bulunduğumuz dizine gore goreceli yol halıne geritiyor
  def self.to_filelist(path) # static erisimli klasorun içindeki tüm dosyaların listesini donduren bir metod tanımladık
    File.directory?(path) ?
      FileList[File.join(path, '*')].select { |f| File.file?(f) } :
      [path]
  end
end

def png_comment(file, string) # png lerin meta datasına yorum yazan bir fonksiyon
  require 'chunky_png'
  require 'oily_png'

  image = ChunkyPNG::image.from_file(file)
  image.metadata['Comment'] = 'raked'
  image.save(file)
end

def png_optim(file, threshold=40000)   # pngleri bash daki pngnq programıyla optimze edip basarılı olrsa bide meta datasına yorum yazan fonk
  return if File.new(file).size < threshold
  sh "pngnq -f -e .png-nq #{file}"
  out = "#{file}-nq"
  if File.exist?(out)
    $?.success? ? File.rename(out, file) : File.delete(out)
  end
  png_comment(file, 'raked')
end

def jpg_optim(file)# jpgleri bash daki jpegoptim programıyla optimze edip basarılı olrsa bide meta datasına yorum yazan fonk
  sh "jpegoptim -q -m80 #{file}"
  sh "mogrify -comment 'raked' #{file}"
end

def optim # alttaki klasölerdeki tüm resimleri (jpg png) optimize eden fonk
  pngs, jpgs = FileList["**/*.png"], FileList["**/*.jpg", "**/*.jpeg"]
  # alt klasölerdeki tüm jpg pngleri seçiyoruz
  [pngs, jpgs].each do |a|
    a.reject! { |f| %x{identify -format '%c' #{f}} =~ /[Rr]aked/ }
  end  # meta datalarında daha onceden optimize ettiğimiz dosyalara eklediğimiz raked yorum satırına sahip olanları çıkar

  (pngs + jpgs).each do |f|
    w, h = %x{identify -format '%[fx:w] %[fx:h]' #{f}}.split.map { |e| e.to_i } # resim boyularını oğren
    size, i = [w, h].each_with_index.max
    if size > iMAGE_GEOMETRY[i] # eğer rasim boyutu daha buyukse 
      arg = (i > 0 ? 'x' : '') + iMAGE_GEOMETRY[i].to_s
      sh "mogrify -resize #{arg} #{f}"
    end # bunları yeniden boyutlandır
  end

  pngs.each { |f| png_optim(f) }
  jpgs.each { |f| jpg_optim(f) }

  (pngs + jpgs).each do |f|
    name = File.basename f
    FileList["*/*.md"].each do |src|
      sh "grep -q '(.*#{name})' #{src} && touch #{src}"
    end # optimize ettiğimiz resimlere bağımlı olan tüm slaytları yeniden üretilmesi gerekiyor
  end # bunların son değişme zamanlarını şimdiye çekerek bir sonraki rake komutunda yeniden oluşmasını istiyoruz
end  # aceba buraya bi sh rake .. yazsak da bir sonraki rake komutunu beklemesek daha iyi olmazmıydı ?

default_conffile = File.expand_path(DEFAULT_CONFFiLE)
# altdizinlerin yapılandırma dosyalarına erişmek için mutlak yol kullanıyoruz
FileList[File.join(PRESENTATiON_DiR, "[^_.]*")].each do |dir| # sunumlar klasarundeki herbir klasor için sunum bnilgilerini üret
  next unless File.directory?(dir) # tabiki kendisi klasor olmayanları pass geç
  chdir dir do
    name = File.basename(dir)
    conffile = File.exists?('presentation.cfg') ? 'presentation.cfg' : default_conffile
    config = File.open(conffile, "r") do |f|
      PythonConfig::ConfigParser.new(f)  # python config parser ile ayarları üret
    end
     # buradan sonra bir dizi handle edilmemeiş birdizi hata kodu geliyor
     # hatalarla aranıyor ve hata bulunursa hata mesajı ve 1 kodu ile çıkılıyor
    landslide = config['landslide']
    if ! landslide
      $stderr.puts "#{dir}: 'landslide' bolumu tanimlanmamis"
      exit 1  
    end

    if landslide['destination']
      $stderr.puts "#{dir}: 'destination' ayari kullanilmis; hedef dosya belirtilmeyin"
      exit 1
    end

    if File.exists?('index.md') # burada kullanıcıya index.md veya presantation .md diye iki seçenekten birini kullanma hakkı verilmiş fakat index daha oncelikli
      base = 'index'
      ispublic = true
    elsif File.exists?('presentation.md')
      base = 'presentation'
      ispublic = false
    else
      $stderr.puts "#{dir}: sunum kaynagi 'presentation.md' veya 'index.md' olmali"
      exit 1
    end

    basename = base + '.html' #oluşturacağımız dosyanın adını daha doğrusu uzantısını oluşturuyoruz
    thumbnail = File.to_herepath(base + '.png') # fileye yaptığımız monkey pach ı hatırladık mı ?
    target = File.to_herepath(basename) # hedef dosyayı belirledik

    deps = []
    (DEPEND_ALWAYS + landslide.values_at(*DEPEND_KEYS)).compact.each do |v|
      deps += v.split.select { |p| File.exists?(p) }.map { |p| File.to_filelist(p) }.flatten
    end # tüm bağımlılıkları belirliyoruz bunları (media baska larıda eklenebilir) klasorunde isimli klasordeki aynı klasordeki belirttiğimiz uzantılarda olan tüm dosyaları olarak belirtiyoruz
    

    deps.map! { |e| File.to_herepath(e) }# tüm adresleri töreli hale getir
    deps.delete(target)
    deps.delete(thumbnail)

    tags = []
   #  klasorun içinde aşşağıdaki taskları yerine getir mesi için bir sözlük oluştur argumanlarıda karşılarındaki değişkenler
   presentation[dir] = {
      :basename  => basename, # uretecegimiz sunum dosyasinin baz adi
      :conffile  => conffile, # landslide konfigurasyonu (mutlak dosya yolu)
      :deps      => deps, # sunum bagimliliklari
      :directory => dir,  # sunum dizini (tepe dizine goreli)
      :name      => name, # sunum ismi
      :public    => ispublic, # sunum disari acik mi
      :tags      => tags, # sunum etiketleri
      :target    => target, # uretecegimiz sunum dos("configyasi (tepe dizine goreli)
      :thumbnail => thumbnail,  # sunum icin kucuk resim
    }
  end
end

presentation.each do |k, v|
  v[:tags].each do |t|
    tag[t] ||= []
    tag[t] << k
  end
end #sözlükdeki tümgörevleri yerine getir

tasktab = Hash[*TASKS.map { |k, v| [k, { :desc => v, :tasks => [] }] }.flatten]
# genel görevleri yerine gertir 
presentation.each do |presentation, data|
  ns = namespace presentation do
    file data[:target] => data[:deps] do |t| 
      chdir presentation do
        sh "landslide -i #{data[:conffile]}"
        sh 'sed -i -e "s/^\([[:blank:]]*var hiddenContext = \)false\(;[[:blank:]]*$\)/\1true\2/" presentation.html'
        unless data[:basename] == 'presentation.html'
          mv 'presentation.html', data[:basename]
        end # presentetion .html diye bir dosya oluştru sonra bunun adını basename değişkeni ile değiştir
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
    end  # cutycapt programını kullanarak resimleri düzenle sonra optimize et

    task :optim do
      chdir presentation do
        optim
      end
    end  # optin fonsiyonunu çağır #basitec tümresimleri organize ediyordu o fonksiyon diyebiliriz

    task :index => data[:thumbnail]

    task :build => [:optim, data[:target], :index]

    task :view do
      if File.exists?(data[:target])
        sh "touch #{data[:directory]}; #{browse_command data[:target]}"
      else
        $stderr.puts "#{data[:target]} bulunamadi; once insa edin"
      end
    end #dosya varsa yeniden oluşturun

    task :run => [:build, :view]

    task :clean do
      rm_f data[:target]
      rm_f data[:thumbnail]
    end #dosyaları temizle

    task :default => :build
  end

  ns.tasks.map(&:to_s).each do |t|
    _, _, name = t.partition(":").map(&:to_sym)
    next unless tasktab[name]
    tasktab[name][:tasks] << t
  end #bu altgorevleri gorev tablosuna iliştir
end

namespace :p do
  tasktab.each do |name, info|
    desc info[:desc]
    task name => info[:tasks]
    task name[0] => name
  end
  # dinamik olarak olşturduğumuz taskları üst isim uzayına  aktar
  task :build do
    index = YAML.load_file(iNDEX_FiLE) || {}
    presentations = presentation.values.select { |v| v[:public] }.map { |v| v[:directory] }.sort
    unless index and presentations == index['presentations']
      index['presentations'] = presentations
      File.open(iNDEX_FiLE, 'w') do |f|
        f.write(index.to_yaml)
        f.write("---\n")
      end # dosyaları oluştur komutu
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
  end  # oluşturduğumuz gorev menusunu sun ve seçimi al ve gerekli gorevi icraet
  task :m => :menu
end

desc "sunum menusu"
task :p => ["p:menu"]
task :presentation => :p

