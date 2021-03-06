#' Download and unpack compressed data from repositories
#' 
#' Downloads a list of tgz files from a list of repos and unpacks them
#' 
#' @param input a vector of files to be downloaded or a cfg list with settings to be used (e.g. containing
#' cfg$input, cfg$repositories). Settings in the config list will be overwritten by other arguments of
#' this function if they are not set to NULL
#' @param targetdir directory the files should be downloaded and extracted to
#' @param repositories a list of repositories (please pay attention to the list format!) in which the files 
#' should be searched for. Files will be searched in all repositories until found, always starting with the 
#' first repository in the list. The argument must have the format of a named list with the url of the repository
#' as name and a corresponding list of options such as username or password to access the repository as value. If
#' no options are required the value has to be NULL. (e.g. 
#' list("ftp://my_pw_protected_server.de/data"=list(user="me",password=12345), "http://free_server.de/dat"=NULL))
#' @param debug switch for debug mode with additional diagnostic information
#' @return Information about the download process in form of a data.frame with data sets as row names and repositories
#' (where it was downloaded from) and corresponding md5sum as columns
#' @author Jan Philipp Dietrich
#' @importFrom utils untar
#' @export

download_unpack <- function(input, targetdir="input", repositories=NULL, debug=FALSE) {
  
  if(is.list(input)) {
    files <- input$input
    if(is.null(repositories))        repositories <- input$repositories
    if(is.null(debug))               debug <- input$debug
  } else {
    files <- input
  }
  
  ifiles <- files
  
  if(!dir.exists(targetdir)) dir.create(targetdir)
  
  # create curl handle
  if(any(grepl("://",names(repositories)))) {
    if(!requireNamespace("curl", quietly = TRUE)) stop("The package curl is required for downloading files!")
  }
  
  .unpack <- function(file, filepath, repo, found) {
    message("    -> ",file)
    return(rbind(found,data.frame(row.names=file,repo=repo,path=filepath,md5=tools::md5sum(filepath), stringsAsFactors=FALSE)))
  }
  
  message("Load data..")
  found <- NULL
  for(repo in names(repositories)) {
    message("  try ",repo)
    if(grepl("://",repo)) {
      h <- try(curl::new_handle(verbose=debug, .list=repositories[[repo]]),silent = !debug)
      tmp <- try(curl::curl_fetch_memory(repo, handle=h)$status_code, silent = !debug)
      if(tmp != 200 &  !grepl("scp://",repo)) {
        message("    repository access failed .. skip repository!")
        next
      }
    } else if(!file.exists(repo)) {
      message("    repository access failed .. skip repository!")
      next 
    }
    for(file in files) {
      path <- paste0(sub("/$","",repo),"/",file)
      if(grepl("://",repo)) {
        tmpdir <- ifelse(debug,targetdir,tempdir())
        tmp <- try(curl::curl_download(path,paste0(tmpdir,"/",file),handle=h),silent = !debug)
        if(!("try-error" %in% class(tmp))) {
          files <- files[-match(file,files)]
          found <- .unpack(file, paste0(tmpdir,"/",file), repo, found)
        }
      } else if(file.exists(path)) {
        files <- files[-match(file,files)]
        found <- .unpack(file, path, repo, found)
      }
    }
    if(length(files)==0) break
  }
  if(length(files)>0) {
    tmp <- paste0("Following files not found:\n  ",paste(files, collapse = "\n  "))
    warning(tmp)
    message(tmp)
  }
  if(is.null(found)) {
    cat("\n")
    stop("No file could be found!")
  } 
  #sort files in intial order and unpack
  found <- found[intersect(ifiles,rownames(found)),]
  message("..unpack files..")
  for(f in rownames(found)) {
    message(" -> ",f)
    untar(found[f,"path"],exdir=targetdir)
  }
  message("..done")
  
  source_log <- paste0(targetdir,"/source_files.log")
  if(file.exists(source_log)) {
    previous_files <- readLines(source_log, warn=FALSE)
    source_log_content <- c(ifiles,"","previously derived from:",previous_files)
  } else {
    source_log_content <- ifiles
  }
  writeLines(source_log_content,source_log)
  
  if(!debug) found$path <- NULL
  attr(found,"warnings") <- warnings()
  return(found)
}