def createPdf(fileName)
    exam = YAML.load_file("_exams/" + fileName)
	title = (exam['title'] || 'ne yazik ki bu sinavin basligi yok')
    footer = (exam['footer'] || 'size basarilar dileyim mi')
    q = (exam['q'] || {})
    list = []
    for i in q
		unless File.directory?("_includes/q/" + i)
			list << File.read("_includes/q/" + i)
		end
    end
    temp = ERB.new(File.read("_templates/exam.md.erb")).result(binding)
	a = fileName[0..-5] + '.md'
    f = File.open(a, 'w')
    f.write(temp)
    f.close()
    sh "markdown2pdf #{a} "
    sh "rm -f #{a}"
end

def dependsList(file) 
    exam = YAML.load_file("_exams/" + file)
	q = (exam['q'] || {})
	list = [File.ctime("_exams/" + file)]
	for i in q
		unless File.directory?("_includes/q/" + i)
			media = File.read("_includes/q/" + i)
			media = /\!\[.*.\]\(.*.\)/.match(media)
			if media != nil
				media.to_a.each  do |a|
					mediaFileNames = /\(.*.\)/.match(a).to_s[1..-2]
					list << File.ctime(mediaFileNames)
				end
			end
			list << File.ctime("_includes/q/" + i)
		end
    end
    list
end 

def depensChanged?(time,list) 
    if time == nil
     return true
    end
    for i in list
		if (i > time)
			return true
		end
	end
	return false
end
require 'yaml'
require 'erb'

task :exam do
  Dir.foreach("_exams") do |file|
    unless  File.directory?("_exams/" + file) 
		if File.exist?(file[0..-5] + ".pdf")
			file_date = File.ctime(file[0..-5] + ".pdf") 
		end
        if depensChanged?(file_date, dependsList(file))
			createPdf(file)
			puts file
		end
    end
  end
end

task :default => :exam
