## REST server inside Bud - API Documentation
##### Note
* Only accepts and returns JSON data

##### Issues
* Cannot remove a row yet
* Cannot add rule or view list of rules yet

##### All failed response will have this format
    Status: 200 OK
    {
        'error' : 'error message here'
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
* `type` type of collection _(only support `table` for now)_
* `collection_name` name of collection
* `keys` a list of keys, ie. `[:test_key_1, :test_key_2]`
* `values` a list of values, ie. `[:test_val_1, :test_val_2, :test_val_3]`

##### Success response
    Status: 200 OK
    {
        'success' : "Added 'collection_type' 'collection_name'"
    }


### 4) Insert row
Insert row(s) into a collection

    POST /add_rows
##### Parameters
* `collection_name` the name of the collection to be added
* `op` the operation, _(only support `<=` for now)_
* `rows` the list of rows to be inserted, ie. `[ [:k1, :k2, :v1, :v2], [:k3, :k4, :v3, :v4] ]`

##### Success response
    Status: 200 OK
    {
        'success' : "Added rows to collection 'test_table_1'"
    }


### 5) Remove row
_**TODO:**  to be implemented_  
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
_**TODO:**  to be implemented_  
Get a list of rules currently associated with the bud instance

    GET /rules

##### Success response
    Status: 200 OK
    {
        'rules' : [
            "table1 <= table2.join(table3)",
            "stdio <~ table1"
        ]
    }


### 7) Add rule
_**TODO:**  to be implemented_  
Add a rule to the bud instance

    POST /add_rule
##### Parameters
* `lhs` the table on the left side of the rule
* `op` the operation, one of `<=`, `<+`, `<~`, `<-`, `<+-` or `<=-`
* `rhs` the expression on the right side of the rule

##### Success response
    Status: 200 OK
    {
        'success' : "Added rule to bud"
    }
