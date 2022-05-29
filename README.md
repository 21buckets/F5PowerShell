# F5PowerShell
A repository for F5 PowerShell functions


## Set-F5UrlCategoryChanges

### Overview
This function is used to programatically update the F5 Big-IP APM Secure Web Gateway custom URL categories based on a provided file. It has the ability to:
* add new categories and URLs
* delete categories
* modify (add/delete) URLs from existing categories


The function compares what is currently set on the F5 to reduce the amount of change required, meaning it will only modify the required changes each time it is executed.

The functions are written for a specific use case where the provided list of URL categories was in a format that could not be changed by me.
To make this more flexible, there is a separate function "Convert-InputURLCategoriesToHash" that converts the input data to a hash table for easier manipulation. 

At some stage I might make this into a larger F5 utilities PowerShell Module, but for now it is just a set of functions

### Dependencies

The main function is dependent on the [pwshf5 module](https://github.com/21buckets/pwshf5) written by Cale Robertson, but forked by me to add additional functions that werent available. 


### Usage

`Set-F5UrlCategorChanges -url_category_content_path "<path_to_file>" -debug_logging -allow_deletion_urls -allow_deletion_categories -prefix_category_name "auto_"`

where:

`url_category_content_path`: path to the URL categories provided by the user.   

`debug_logging`: Log messages will only be provided if this flag is used.  

`allow_deletion_urls`: As a safety precaution, deletion of URLs from categories will only occur if this flag is used. 

`allow_deletion_categories`: As a safety precaution, deletion of entire categories will only occur if this flag is used. 

`prefix_category_name`: This allows you to provide a prefix to set on the URL categories, which then allows you to run this command against categories matching that prefix for deletion operations. This is ideal if you have custom categories that aren't set as part of this automation (i.e. a third party (or multiple) provides a set of URL categories) and  you want to make sure you don't delete them by mistake.
e.g. a prefix of "auto_" will take the URL category provided in the input, and add "auto_" to the start of the category when it is added to the F5.

