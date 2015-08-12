class Dataset

    constructor : (@App) ->
        routeName = "dataset"

        @App.router.get "/#{routeName}", @getDatasets
        @App.router.get "/#{routeName}/:id", @getDataset
        @App.router.post "/#{routeName}", @postDataset
        @App.router.delete "/#{routeName}/:id", @deleteDataset
       
    deleteDataset : (req , res)=>
        @App.Models.Data.remove {"id._id" : @App.objectID(req.params.id) } , {w : 1}, (err,data)=>
            if !err and data 
                @App.Models.Dataset.remove {_id : @App.objectID(req.params.id)},{w : 1}, (err,data)=>
                    console.log "Remove"
                    return @App.sendContent req, res, data
    getDatasets : (req, res)=>
        @App.Models.Dataset.find({}).toArray (err,data)=>
            if !err
                if data
                    return @App.sendContent req, res, data
                else
                    return @App.sendContent req, res, []
            else
                return @App.sendAdminError req,res, err  
    getDataset: (req, res)=>
        if !req.params.id 
            return @App.sendError req, res, 404, "No ID!" 
        @App.Models.Dataset.findOne {}, (err,data)=>
            if !err
                if data
                    return @App.sendContent req, res, data
                else
                    return @App.sendError req, res, 404, "No data"
            else
                return @App.sendAdminError req, res, err
    postDataset : (req, res)=>
        if !req.body.name
            return @App.sendError req, res, 404, "No name!"
        if !req.body.url 
            return @App.sendError req, res, 404, "No URL!"
        if !req.body.key
            return @App.sendError req, res, 404, "No key!"
        
        dataset = 
            name : req.body.name 
            url : req.body.url
            key : req.body.key
            
        @App.Models.Dataset.insert dataset , (err,data)=>
            if !err
                if data 
                    return @App.sendContent req, res, data
            else
                return @App.sendAdminError req, res, err 
module.exports = Dataset 