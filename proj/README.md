## REST server inside Bud - API Documentation
##### Note
* Only accepts and returns JSON data

##### All failed response will have this format
    Status: 200 OK
    {
        'error' : 'error message here',
        'stack_trace' : 'stack trace here if any (@DEBUG == true)'
    }


### 1) List collections
Return a list of all user-defined (non-builtin) collections by the `/add_collection` API  
If the user has not defined any collection for a type, it will not be shown in the response

    GET /collections
##### Success response
    Status: 200 OK
    {
        'collections': {
            'tables': [
                'table1',
                'table2',
            ],
            'scratches': [
                'scratch1'
            ],
            'channels': [
                'channel1'
            ]
        }
    }


### 2) List collection content
Return all the content in the collection with the given `collection_name`

    GET /content
##### Parameters
* `collection_name` name of collection

##### Success response
    Status: 200 OK
    {
        'content': [
            ['k1', 'v1'],
            ['k2', 'v2'],
            ['k3', 'v3'],
            ['k4', 'v4']
        ]
    }


### 3) Add collection
Add a collection to the bud instance

    POST /add_collection
##### Parameters
* `type` type of collection, one of `table`, `scratch`, `input_interface`, `output_interface` or `channel`
* `collection_name` name of collection
* `keys` a list of keys, ie. `[:test_key_1, :test_key_2]`
* `values` a list of values, ie. `[:test_val_1, :test_val_2, :test_val_3]`

##### Success response
    Status: 200 OK
    {
        'success' : "Added '<collection_type>' '<collection_name>'"
    }


### 4) Insert row
Insert row(s) into a collection

    POST /add_rows
##### Parameters
* `collection_name` the name of the collection to be added
* `op` the operation, one of `<=`, `<+` or `<~`
* `rows` the list of rows to be inserted, ie. `[ [:k1, :k2, :v1, :v2], [:k3, :k4, :v3, :v4] ]`

##### Success response
    Status: 200 OK
    {
        'success' : "Added rows to collection 'test_table_1'"
    }


### 5) Remove row
Remove row(s) into a collection (with `<-`)

    POST /remove_rows
##### Parameters
* `collection_name` the name of the collection to be removed
* `rows` the list of rows to be removed, ie. `[ [:k1, :k2, :v1, :v2], [:k3, :k4, :v3, :v4] ]`

##### Success response
    Status: 200 OK
    {
        'success' : "Removed rows from collection 'test_table_1'"
    }


### 6) List rules
Get a list of rules currently associated with the bud instance

    GET /rules

##### Success response
    Status: 200 OK
    {
        'rules' : [
            'table1 <= table2.notin(table3, :test_key => :test_key)',
            'stdio <~ table1'
        ]
    }


### 7) Add rule
Add a rule to the bud instance

    POST /add_rule
##### Parameters
* `lhs` the table on the left side of the rule
* `op` the operation, one of `<=`, `<+`, `<~`, or `<-`
* `rhs` the expression on the right side of the rule

##### Success response
    Status: 200 OK
    {
        'success' : "Added rule to bud"
        'rewritten_rule' : '<the rule might get rewritten once added to bud, that version of the rule will be returned here>'
    }


### 8) Tick
Tick the bud instance

    POST /tick
##### Parameters
* `times` optional number of times to tick

##### Success response
    Status: 200 OK
    {
        'success' : "Ticked the bud instance n times"
    }
