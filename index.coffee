sift = require 'sift'
MongoOplog = require 'mongo-oplog'
Promise = require 'bluebird'
HashMap = require('hashmap').HashMap
EventEmitter = require('events').EventEmitter

watchers = {}
getWatcher = (collection) ->
	host = collection.db.serverConfig._state.master.host
	port = collection.db.serverConfig._state.master.port

	address = collection.db.options.url.replace /\/[^\/]+$/, '/local'
	if not watchers[address]
		watchers[address] = new Promise (resolve, reject) ->
			watcher = MongoOplog address
			watcher.tail ->
				resolve watcher

	return watchers[address]

module.exports = class CachedFind extends EventEmitter

	constructor: (@collection, @query) ->
		ns = collection.db.databaseName + '.' + collection.collectionName

		@sifter = sift query
		@documents = new HashMap()
		@refresh()

		@watcher = getWatcher(collection)
		@watcher.then (watcher) =>
			@emit 'tailing', watcher
			watcher.on 'insert', (event) =>
				if event.ns is ns
					if @check event.o
						@add event.o
			
			watcher.on 'update', (event) =>
				if event.ns is ns
					if @check event.o
						@add event.o
					else
						@remove event.o._id

			watcher.on 'remove', (event) =>
				if event.ns is ns
					@remove event.o._id

	refresh: (callback) ->
		@query = new Promise (resolve, reject) =>
			@documents.clear()
			@collection.find(@query).each (err, row) =>
				if err
					@emit 'error', err
					reject err

				else if row
					@documents.set row._id, row

				else
					@emit 'init', @documents.values()
					resolve()		

	check: (document) ->
		@sifter.test document

	add: (document) ->
		@documents.set document._id, document
		@emit 'add', document

	remove: (id) ->
		if @documents[id]
			@documents.remove id
			@emit 'remove', id

	get: (cb) ->
		good = => cb null, @documents.values()
		bad = (reason) -> cb reason

		@query.then good, bad
