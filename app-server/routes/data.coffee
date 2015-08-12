
ObjectId = require('mongodb').ObjectID;
redis = require("redis").createClient();
class Data
    constructor: (@App)->  
        routeName = "data"

        @App.router.get "/#{routeName}/singleData/:datasourceid", @getSingleData
        @App.router.get "/#{routeName}", @getData
    #This route is used for text related data
    getSingleData : (req, res)=>
        start = null
        end = null
        conditions = {}
        objectIdWithTimestamp = (date)=>
            return ObjectId.createFromTime date.getTime()/1000
        if req.query.start && req.query.end 
            startNum = parseInt(req.query.start)
            endNum = parseInt(req.query.end)
            if !(startNum > endNum)
            #Start should always be more than end
                return @App.sendError req, res, 400, "Start should always be more than end!"
            else
                start = new Date(parseInt(req.query.start))
                end = new Date(parseInt(req.query.end))
    
        if start != null && end != null
            conditions = {_id : { $gt : objectIdWithTimestamp(end) , $lt : objectIdWithTimestamp(start)}}
        else
            conditions = {}
        conditions["id._id"] = @App.objectID(req.params.datasourceid)
        @App.Models.Data.find(conditions).toArray (err, data)=>
            if !err and data 
                return @App.sendContent req, res, data
            else
                console.log "hello ddfsf"

    getDataBasedOnQueryNew : (req, res, redis_key)=>
            #By default, load all entries for past 24 hrs

            objectIdWithTimestamp = (date)=>
                return ObjectId.createFromTime date.getTime()/1000

            conditions = {}
            start = null
            end = null 
            if req.query.start && req.query.end
                startNum = parseInt(req.query.start)
                endNum = parseInt(req.query.end)
                if !(startNum > endNum)
                #Start should always be more than end
                    return @App.sendError req, res, 400, "Start should always be more than end!"
                else
                    start = new Date(startNum)
                    end = new Date(endNum)
                    console.log start
                    console.log end 
                    
                    conditions = {_id : { $gt : objectIdWithTimestamp(end) , $lt : objectIdWithTimestamp(start)}}    
            else
                #return entries for last 24 hrs by default
                startDate = new Date(new Date().getTime())
                endDate  = new Date(new Date().getTime() - (1 * 24 * 60 * 60 * 1000) )
                
                console.log startDate
                console.log endDate

                conditions = {_id : { $gt : objectIdWithTimestamp(endDate) , $lt : objectIdWithTimestamp(startDate)}}
                #conditions = {}
            if req.query.parkid
                conditions["park._id"] = @App.objectID(req.query.parkid)
            conditions["id.name"] = 
                $in : ["Yahoo Humidity", "Yahoo Temperature", "Wind Speed"]
            console.log conditions
            @App.Models.Data.find(conditions).toArray (err, datas)=>
                if !err and datas
                    parksArray = [] #This is what gets pushed to user eventually
                    for data in datas 
                        if data["park"] isnt null and data["data"] isnt null and data
                            found = false
                            #Find park to put into, if nothing then push to parksArray
                            for park in parksArray
                                if park["_id"].toHexString() is data["park"]["_id"].toHexString()
                                    found = true
                                    delete data.park
                                    park["data"].push data
                                    break;
                            if !found
                                newPark = data.park
                                delete data.park #Prevent recursive bullshit
                                newPark["data"] = []
                                newPark["data"].push data
                                newPark["name"] = newPark["parkName"][0]
                                delete newPark["parkName"]
                                parksArray.push newPark
                    #After getting all the data group in parks, now need to group the datasource
                    for park in parksArray
                        dataSameDS = []#The 2d array
                        for data in park["data"]
                            #Try to find a datasource to group to
                            foundDS = false
                            for dataSource in dataSameDS
                                if dataSource[0]["id"]["_id"].toHexString() is data["id"]["_id"].toHexString()
                                    foundDS = true
                                    dataSource.push data
                                    break;
                            if !foundDS
                                dataSameDS.push [data]
                        park["data"] = dataSameDS
                    #Accumulates the timeCollected entries
                    for park in parksArray
                        allTimeCollected = []
                        allTimeCollectedCount = []
                        for ds in park["data"]
                            for data in ds
                                formattedDate = new Date(parseInt(new Date(data["timeCollected"]).getTime()/(1000 * 60))*(1000 * 60))
                                data["timeCollected"] = formattedDate
                                index = allTimeCollected.indexOf(formattedDate.toString())
                                if index == -1
                                    allTimeCollectedCount.push 1
                                    allTimeCollected.push formattedDate.toString()
                                else
                                    #allTimeCollected has to be pushed to database?
                                    allTimeCollectedCount[index] += 1
                        park["timeCollected"] = allTimeCollected
                redis.set redis_key, JSON.stringify(parksArray)
                return @App.sendContent req, res, parksArray
    getData : (req, res)=>
        redis_key = "data_latest"
        if Object.keys(req.query).length > 0
            redis_key = "data_latest_#{JSON.stringify(req.query)}"
        else
            console.log "no query"
        #redis.get redis_key,(err,data)=>
         #   if data is null
        return @getDataBasedOnQueryNew req, res,redis_key
         #   else
          #     console.log "Getting results from #{redis_key}" 
          #     return @App.sendContent req, res, JSON.parse(data)
        
        
module.exports = Data