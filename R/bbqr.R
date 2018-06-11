#' @title Create a bare-bones message queue in R.
#' @description See the README at
#'   [https://github.com/wlandau/bbqr](https://github.com/wlandau/bbqr)
#'   and the examples in this help file for instructions.
#' @export
#' @param path Character string giving the file path of the queue.
#'   The `bbqr()` function creates a folder at this path to store
#'   the messages.
#' @examples
#'   path <- tempfile() # Define a path to your queue.
#'   path # This path is just a temporary file for demo purposes.
#'   q <- bbqr(path) # Create the queue.
#'   list.files(q$path) # The queue lives in this folder.
#'   q$list() # You have not pushed any messages yet.
#'   # Let's say two parallel processes (A and B) are sharing this queue.
#'   # Process A sends Process B some messages.
#'   # You can only send character strings.
#'   q$push(title = "Hello", message = "process B.")
#'   q$push(title = "Calculate", message = "sqrt(4)")
#'   q$push(title = "Calculate", message = "sqrt(16)")
#'   q$push(title = "Send back", message = "the sum.")
#'   # See your queued messages.
#'   q$list()
#'   q$count()
#'   q$empty()
#'   # Now, let's assume process B comes online. It can consume
#'   # some messages, locking the queue so process A does not
#'   # mess up the data.
#'   q$pop(2) # Return and remove the first messages that were added.
#'   # With those messages popped, we are farther along in the queue.
#'   q$list()
#'   q$list(1) # You can specify the number of messages to list.
#'   # But you still have a log of all the messages that were ever pushed.
#'   q$log()
#'   # q$pop() with no arguments just pops one message.
#'   # Call pop(-1) to pop all the messages at once.
#'   q$pop()
#'   # There are more instructions.
#'   q$pop()
#'   # Let's say Process B follows the instructions and sends
#'   # the results back to Process A.
#'   q$push(title = "Results", message = as.character(sqrt(4) + sqrt(16)))
#'   # Process A now has access to the results.
#'   q$pop()
#'   # Destroy the queue's files.
#'   q$destroy()
#'   # This whole time, the queue was locked when either Process A
#'   # or Process B accessed it. That way, the data stays correct
#'   # no matter who is accessing/modifying the queue and when.
bbqr <- function(path){
  R6_bbqr$new(path = path)
}

R6_bbqr <- R6::R6Class(
  classname = "R6_bbqr",
  private = list(
    queue_dir = character(0),
    queue_file = character(0),
    count_file = character(0),
    lock_file = character(0),
    connection = NULL,
    exclusive = function(code){
      on.exit(filelock::unlock(lock))
      lock <- filelock::lock(private$lock_file)
      force(code)
    },
    get_count = function(){
      readRDS(private$count_file)
    },
    bbqr_peek = function(){
      readRDS(private$queue_file)
    },
    bbqr_pop = function(){
      saveRDS(as.integer(private$get_count() - 1), private$count_file)
      unserialize(private$connection)
    },
    bbqr_push = function(data){
      saveRDS(as.integer(private$get_count() + 1), private$count_file)
      serialize(data, connection = private$connection, xdr = FALSE)
      invisible()
    }
  ),
  public = list(
    initialize = function(path){
      private$queue_dir <- fs::dir_create(path)
      private$queue_file <- file.path(private$queue_dir, "queue.rds")
      private$count_file <- file.path(private$queue_dir, "count.rds")
      private$lock <- file.path(private$queue_dir, "lock")
      private$exclusive({
        fs::file_create(private$queue_file)
        fs::file_create(private$count_file)
        if (length(private$get_count()) < 1){
          saveRDS(as.integer(0), file = private$count_file)
        }
      })
      self$connect() 
    },
    path = function(){
      private$queue_dir
    },
    count = function(){
      private$exclusive(private$get_count())
    },
    empty = function(){
      self$count() < 1
    },
    peek = function(){
      private$exclusive(private$peek_head())
    },
    pop = function(){
      private$exclusive(private$pop_head())
    },
    push = function(data){
      private$exclusive(private$push_data(data))
    },
    connect = function(){
      if (is.null(private$connection)){
        private$connection <- file(private$queue_file, "w+b")
      }
    },
    disconnect = function(){
      if (!is.null(private$connection)){
        close(private$connection)
        private$connection <- NULL
      }
    },
    destroy = function(){
      self$disconnect()
      unlink(private$queue_dir, recursive = TRUE, force = TRUE)
    }
  )
)
