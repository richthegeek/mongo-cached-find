sift = require 'sift'
MongoOplog = require 'mongo-oplog'
Promise = require 'bluebird'
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
		@documents = {}
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
			@collection.find(@query).toArray (err, rows) =>
				@documents = {}

				if err
					@emit 'error', err
					reject err

				else
					for row in rows
						@documents[row._id] = row

					@emit 'init', rows
					resolve()		

	check: (document) ->
		@sifter.test document

	add: (document) ->
		@documents[document._id] = document
		@emit 'add', document

	remove: (id) ->
		if @documents[id]
			delete @documents[id]
			@emit 'remove', @documents[id]

	get: (cb) ->
		good = => cb null, (doc for id, doc of @documents when doc)
		bad = (reason) -> cb reason

		@query.then good, bad
