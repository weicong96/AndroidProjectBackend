http = require('http')
config = require("./config")
mongodb = require('mongodb').MongoClient
express = require('express')
bodyParser = require("body-parser")
ObjectId = require('mongodb').ObjectID;
request = require("request")
fs = require("fs")
xml2js = require("xml2js")
client = require('beanstalk_client').Client;
redis = require("redis").createClient()
class App
    Models : {}
    constructor : ->
        @config = config
        @Q = require("q")
        @mongo = mongodb.connect @config.mongodb.url,(err, db)=>
            if !err
                if db
                    @mongo = db
                    console.log "Mongodb started"
                    @initModels()
                    #setInterval ()=>
                    #    @setupParks()
                    #, 10 * 1000
                    @setupFormula()
    fetchedPatternsDataset : []
    getDataInterval : (result)=>
        getData = (_datasource, _park,formulaid) =>
            deferred = @Q.defer()
            
            #Handle the parsing of park address, if needed
            originalDSURL = _datasource.url
            url = null
            if _park
                url = _datasource.url.replace "+_address_+", _park.address
                url = _datasource.url.replace "+_lat_+", _park.lat
                url = _datasource.url.replace "+_lng_+", _park.lng
            else
                url = _datasource.url
            
            if url
                request url, (error, response)=>
                    #This is to prevent 503 or any other errors
                    if !error and response.statusCode is 200 
                        #Method to handle parsing of json or xml that has been transformed to json
                        parseJSON = (response, _datasource, parse)=>
                            #To add : conditionals for data sets
                            parseResponse = response
                            #If parse is true, means response is pure JSON string, not xml string yet
                            if parse is true
                                parseResponse = JSON.parse(response)
                                
                            currentData = parseResponse
                            #Not a valid address
                            if currentData["cod"] is "404"
                                console.log "No city"
                                return deferred.resolve {timeCollected: new Date(new Date().getTime() + 60 * 60 * 2 * 1000), key : _datasource.key ,data : "No city error", id : _datasource, formulaid : formulaid , park : _park}
                            #for each data key found in ds key, split and access the data
                            for data in _datasource.key.split(".")
                                if currentData[data] instanceof Array
                                    currentData = currentData[data][0]
                                else
                                    if data is "info"
                                        console.log "Info"
                                    #Handling xml
                                    if Object.keys(currentData).indexOf("$") > -1
                                        currentData = currentData["$"]
                                    currentData = currentData[data]

                            _datasource.url = originalDSURL
                            return deferred.resolve {timeCollected: new Date(), key : _datasource.key ,data : currentData, id : _datasource, formulaid : formulaid , park : _park}
                        #Check if xml or json
                        if !(response.body.indexOf("{") > -1 and response.body.indexOf("}") > -1)
                            console.log "I think it's xml"
                            parseString = require('xml2js').parseString;
                            parseString response.body , (err, result)=>
                                parseJSON result, _datasource, false
                        else
                            parseJSON response.body, _datasource, true
                    else
                        return deferred.reject error
            else
                return deferred.reject error
            return deferred.promise
        for status in result.statuses 
            for pattern in status.patterns
                if @fetchedPatternsDataset.indexOf pattern["dataset"]["_id"] > -1 
                    runIntervalFunction = (pattern, result)=>
                            @Models.Dataset.find({_id : @objectID(pattern.dataset._id)}).toArray (err, docs)=>
                                if !err
                                    if docs
                                        promiseArray = [] 
                                        for data in docs
                                                @Models.Park.find({}).toArray (err, parks)=>
                                                    if !err
                                                        if parks
                                                            for _park in parks

                                                                getData(data,_park,result._id.toHexString()).then (results)=>
                                                                    if results
                                                                        if results.data.area 
                                                                            for result in results.data.area 
                                                                                result["element"] = result["$"] 
                                                                                delete result["$"]

                                                                        @Models.Data.insert results,(err,data)=>
                                                                            if !err
                                                                               jobData = 
                                                                                    id : data[0]._id
                                                                                    time : new Date().getTime()
                                                                                @log "#{data[0].id.name} , #{data[0].park.parkName[0]} "
                                                                                @bsPutJob @config.tubeName, JSON.stringify jobData
                                                                                redis.keys "data_latest*", (err,keys)=>
                                                                                    for key in keys
                                                                                        redis.del key, (err,doc)=>
                                                                                            console.log doc
                                                                                console.log "Inserted and created job"
                                                                            else
                                                                                console.log err 
                                                        else
                                                            console.log "Cannot find park"
                                                    else
                                                        console.log err
                                    else
                                        console.log "No data"
                                else
                                    console.log "Error"  
                                @log "Schedules #{ pattern.dataset.name } to run on #{ new Date(pattern.frequency * 60 * 1000 + new Date().getTime())}"  
                    @fetchedPatternsDataset.push pattern["dataset"]["_id"]

                    setInterval (pattern, result)=>
                        runIntervalFunction pattern, result
                    , pattern.frequency * 60  * 1000, pattern, result

                    runIntervalFunction pattern, result
                    @log "Schedules #{ pattern.dataset.name } to run on #{ new Date(pattern.frequency * 60 * 1000 + new Date().getTime())}"
    setupFormula : ()=>
        secondsPassed = 0
        
        #Only use formulas that have been set to using true, reduce load and confusion in system
        @Models.Formula.find({"using" : "true", _id : @objectID("5586582f20b645a832e4adc4")}).toArray (err,docs)=>
            if !err
                console.log docs.length
                for result in docs
                    @getDataInterval result
                console.log "data"
            else
                console.log "Error"+error
    objectID : (id) =>
        return new ObjectId(id)
    log : (text) =>
        console.log "[#{@config.appname}] @ "+new Date() + " : "+text
    setupParks : ()=>
        parser = new xml2js.Parser()
        fs.readFile __dirname+"/../AngularJSDengue/parks.kml", (err,data)=>
            if !err 
                parser.parseString data , (err, result)=>
                    documentLength = result.kml.Document[0].Placemark.length
                    for place in result.kml.Document[0].Placemark
                        coordinates =  place.Point[0].coordinates[0].split(",")
                        lat = coordinates[1]
                        lng = coordinates[0]
                        
                        findPark= (place,data,  lat, lng)=>
                            geocoder = require("geocoder")
                            #geocoder.selectProvider("geonames", {"username": "weicong96"})
                            geocoder.reverseGeocode lat, lng , (err, data)=>
                                if !err 
                                    if data.results.length > 0 && data.results[0].formatted_address isnt ""
                                        park = 
                                            parkName: place.name
                                            lat : data.results[0].geometry.location.lat
                                            lng : data.results[0].geometry.location.lng
                                        park.address = data.results[0].formatted_address
                                        @Models.Park.findOne {address : park.address}, (err,data)=>
                                            if !data
                                                @Models.Park.save park, (err,status)=>
                                                    if !err
                                                        if data
                                                            console.log "Inserted", park.parkName

                                                            @Models.Park.find({}).toArray (err,data)=>
                                                                if !err 
                                                                    if data.length == documentLength
                                                                        console.log "Documents are all inserted!"
                                                    else
                                                        console.log "Error",err
                                else 
                                    console.log err       
                            , {"key": "AIzaSyBHv2Tw9R49ndHncfJdfm2Tnd6sVVm0kBc"}     
                        findPark place,data, lat, lng           
            else
                console.log err
    
    initModels : () =>
        @Models.Formula = @mongo.collection("formula")
        @Models.Data = @mongo.collection("data")
        @Models.Park = @mongo.collection("park")
        @Models.Dataset = @mongo.collection("dataset")

    sendError: (req,res, errorCode, message)=>
        res.status errorCode
        return res.send {"error" : message}
    sendAdminError: (req,res, message)=>
        res.status 500
        return res.send {"error": message}
    sendContent: (req,res, content)=>
        res.status 200
        return res.json content
    bsPutJob : (tubename, jobdata)=>
        data = JSON.stringify jobdata
        client.connect "127.0.0.1:11300", (err,con)=>
            if err
                console.log "Error connecting to beanstalkd #{err}"
            con.use tubename, (err)=>
                con.put 0, 0, 1, data, (err, job_id)=>
                    #console.log "Put job into #{tubename} #{job_id}"
new App()
module.exports = App
