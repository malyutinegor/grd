# PLUGINS
gulp       = require 'gulp'
watch      = require 'gulp-watch'
plumber    = require 'gulp-plumber'
debug      = require 'gulp-debug'
rename     = require 'gulp-rename'
filter     = require 'gulp-filter'
gif        = require 'gulp-if'
concat     = require 'gulp-concat'
ignore     = require 'gulp-ignore'
tap        = require 'gulp-tap'
cache      = require 'gulp-cache'
ico        = require 'gulp-to-ico'
imagemin   = require 'gulp-imagemin'
ar         = require 'gulp-extract-ar'
zip        = require 'gulp-zip'
decompress = require 'gulp-decompress'
moon       = require 'gulp-moon'

through    = require 'through2'
Vinyl      = require 'vinyl'
tarxz      = require 'decompress-tarxz'
beep       = require 'beeper'
merge      = require 'merge-stream'
rcedit     = require 'rcedit'
path       = require 'path'
fs         = require 'fs'
del        = require 'del'

BuildFiles = require './buildfiles.js'
bf = undefined


##############
# BUILDFILES #
##############

BUILDFILES_DIR = "buildfiles"
BUILDFILES =
	version: '0.10.2'
	download: 'https://bitbucket.org/rude/love/downloads/{{path}}'
	platforms:
		linux:
			filename: "love_{{version}}ppa1_{{arch}}.deb"

			prepare: (file) ->
				return file
					.pipe ar()
					.pipe filter 'data.tar.xz'
					.pipe decompress plugins: [tarxz()]
					.pipe filter 'usr/bin/love'
					.pipe rename 'game'

			arches: [
				'i386'
				'amd64'
				'armhf'
			]

		windows:
			filename: "love-{{version}}-{{arch}}.zip"

			prepare: (file) ->
				return file
					.pipe decompress()
					.pipe rename (pth) ->
						arr = pth.dirname.split path.sep
						arr.shift()
						pth.dirname = arr.join path.sep
					.pipe filter ['**', '!love-*']

			arches: [
				'win32'
				'win64'
			]

############
# BUILDERS #
############
BUILDERS =
	linux: (buildfiles, love) ->
		return buildfiles
			.pipe gif 'love', tap (file) ->
				file.contents = Buffer.concat [
					file.contents
					love
				]
			.pipe gif("love", rename "game")

	windows: (buildfiles, love) ->
		return buildfiles
			.pipe ignore ['love.ico', 'lovec.exe', 'changes.txt', 'readme.txt']
			.pipe gif 'love.exe', tap (file) ->
				file.contents = Buffer.concat [
					file.contents
					love
				]
			.pipe gif("love.exe", rename "game.exe")

##########
# CONSTS #
##########

CONFIG_NAME = '/config.lua'


###########
# HELPERS #
###########

error = (err) ->
	beep()
	console.error err

generateGameConfig = (name) -> new Buffer "return require('configs.#{name}')"

addGameConfig = (name) ->
	cfg = generateGameConfig name
	complete = false
	return through.obj (file, enc, cb) ->
		unless complete
			@push new Vinyl
				cwd: '/'
				base: '/'
				path: CONFIG_NAME
				contents: cfg
			complete = true
		if file.path.match CONFIG_NAME
			cb null
		else
			cb null, file

exists = (file) ->
	try
		fs.statSync file
		return true
	catch
		return false

ignorify = (patterns) ->
	return ("!#{p}" for p in patterns)

#########
# TASKS #
#########

moonify = (s) ->
	s.pipe plumber errorHandler: error
		.pipe moon()
		.pipe debug title: 'MoonScript: compiled'
		.pipe gulp.dest 'app'

# WATCH TASKS
gulp.task 'watch:moon', ->
	return moonify watch 'app/**/*.moon', ignoreInitial: false

gulp.task 'moon', ->
	return moonify gulp.src 'app/**/*.moon'
		













# CLEAN TASKS
gulp.task 'clean:buildfiles', (cb) ->
	del ['buildfiles'], cb

gulp.task 'clean:dist', (cb) ->
	del ['dist'], cb

gulp.task 'clean:build', (cb) ->
	del ['build'], cb

gulp.task 'clean:icon', (cb) ->
	del ['icon.ico'], cb

gulp.task 'clean', gulp.parallel('clean:buildfiles', 'clean:dist', 'clean:build', 'clean:icon')










# START TASKS
gulp.task 'start:dist', ->
	ignored = [
		'app/**/docs/**/*'
		'app/**/docs'
		'app/**/spec/**/*'
		'app/**/spec'
		'app/**/*.md'
		'app/**/*.moon'
		'app/**/*.git'
		'app/**/*.rockspec'
		'app/**/LICENSE'
		'app/**/*.sh'
	]
	return gulp.src ['app/**/*', ignorify(ignored)...]
		.pipe gif('*.+(png|jpg|gif|svg)', cache imagemin())
		.pipe addGameConfig 'production'
		.pipe gulp.dest 'dist'

gulp.task 'start:copy-build', ->
	return gulp.src ['buildfiles/**/*']
		.pipe gulp.dest 'build'








# BUILD TASKS

gulp.task 'build:love', ->
	return gulp.src 'dist/**/*'
		.pipe zip 'game.love'
		.pipe gulp.dest 'build'

	# 'build:rcedit'

gulp.task "build:main", ->
	lv = fs.readFileSync 'build/game.love'
	streams = []
	for name, builder of BUILDERS
		platform = BUILDFILES.platforms[name]
		for arch in platform.arches
			files = gulp.src "#{BUILDFILES_DIR}/#{name}/#{arch}/**/*"

			streams.push(builder files, lv
				.pipe gulp.dest "build/#{name}/#{arch}")

	merge streams...

gulp.task 'build:icon', (cb) ->
	unless exists 'icon.ico'
		gulp.src 'app/assets/sprites/icon.png'
			.pipe ico("icon.ico", resize: true)
			.pipe gulp.dest "./"
	else
		return Promise.resolve()

gulp.task 'build:copy-icon', ->
	gulp.src 'icon.ico'
		.pipe rename 'game.ico'
		.pipe gulp.dest 'build/windows/win32/'
		.pipe gulp.dest 'build/windows/win64/'


gulp.task 'build:rcedit', ->
	Promise.all [
		new Promise (resolve, reject) ->
			rcedit 'build/windows/win64/game.exe', {
				icon: 'build/windows/win64/game.ico'
			}, -> 
				resolve()

		new Promise (resolve, reject) ->
			rcedit 'build/windows/win32/game.exe', {
				icon: 'build/windows/win32/game.ico'
			}, -> 
				resolve()
	]





# GET TASKS
gulp.task 'get:buildfiles', ->
	unless exists BUILDFILES_DIR
		bf = new BuildFiles BUILDFILES

		return bf.compiled.stream
			.pipe debug title: 'Loaded buildfile'
			.pipe gulp.dest BUILDFILES_DIR
	else
		return Promise.resolve()



# MIX TASKS

gulp.task 'build', gulp.series(
	gulp.parallel 'get:buildfiles', 'clean:dist', 'clean:build'
	'start:dist', 
	gulp.parallel 'build:love', 'build:icon'
	'build:main'
	'build:copy-icon'
	'build:rcedit'
	)

gulp.task 'default', gulp.series 'build'


