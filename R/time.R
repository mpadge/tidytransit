#' Filter stop times by hour of the day
#' 
#' @param stop_times a gtfs_obj$stop_times dataframe with arrival_time and departure_time 
#'                   created by [set_hms_times()].
#' @return dataframe with only stop times within the hours specified, with time columns as lubridate periods
#' @keywords internal
filter_stop_times_by_hour <- function(stop_times, 
  start_hour, 
  end_hour) {
  # TODO use set_hms_times during import to avoid errors here?
  stopifnot("arrival_time_hms" %in% colnames(stop_times), "departure_time_hms" %in% colnames(stop_times))
  # it might be easier to just accept hms() objects
  dplyr::filter(stop_times, arrival_time_hms > 
                          hms::hms(hours = start_hour) & 
                          departure_time_hms < hms::hms(hours = end_hour))
}

#' Add hms::hms columns to feed
#' 
#' Adds columns to stop_times (arrival_time_hms, departure_time_hms) and 
#' frequencies (start_time_hms, end_time_hms) with times converted with [hms::hms()].
#' 
#' @param gtfs_obj a gtfs object in which hms times should be set, 
#'                the modified gtfs_obj is returned
#' @return gtfs_obj with added hms times columns for stop_times and frequencies
#' @importFrom hms hms
#' @export
set_hms_times <- function(gtfs_obj) {
  stopifnot(is_gtfs_obj(gtfs_obj))
  
  gtfs_obj$stop_times$arrival_time_hms <- 
    hms::hms(hhmmss_to_seconds(gtfs_obj$stop_times$arrival_time))
  gtfs_obj$stop_times$departure_time_hms <- 
    hms::hms(hhmmss_to_seconds(gtfs_obj$stop_times$departure_time))
  
  if(feed_contains(gtfs_obj, "frequencies") && nrow(gtfs_obj$frequencies) > 0) {
    gtfs_obj$frequencies$start_time_hms <- 
      hms::hms(hhmmss_to_seconds(gtfs_obj$frequencies$start_time))
    gtfs_obj$frequencies$end_time_hms <- 
      hms::hms(hhmmss_to_seconds(gtfs_obj$frequencies$end_time))
  }
  
  return(gtfs_obj)
}

#' Returns all possible date/service_id combinations as a data frame
#' 
#' Use it to summarise service. For example, get a count of the number of services for a date. See example. 
#' @return a date_service data frame
#' @param gtfs_obj a gtfs_object as read by [read_gtfs()]
#' @export
#' @examples 
#' library(dplyr)
#' local_gtfs_path <- system.file("extdata", "google_transit_nyc_subway.zip", package = "tidytransit")
#' nyc <- read_gtfs(local_gtfs_path) %>% set_date_service_table()
#' nyc_services_by_date <- nyc$.$date_service_table
#' # count the number of services running on each date
#' nyc_services_by_date %>% group_by(date) %>% count()
set_date_service_table <- function(gtfs_obj) {
  stopifnot(is_gtfs_obj(gtfs_obj))
  
  weekday <- function(date) {
    c("sunday", "monday", "tuesday", 
      "wednesday", "thursday", "friday", 
      "saturday")[as.POSIXlt(date)$wday + 1]
  }
  
  if(all(is.na(gtfs_obj$calendar$start_date)) && 
     all(is.na(gtfs_obj$calendar$end_date))) {
    # TODO validate no start_date and end_date defined in calendar.txt
    date_service_df <- dplyr::tibble(date=lubridate::ymd("19700101"), 
                                     service_id="x") %>% 
      dplyr::filter(service_id != "x")
  } else {
    # table to connect every date to corresponding services (all dates from earliest to latest)
    dates <- dplyr::tibble(
      date = seq(
        min(gtfs_obj$calendar$start_date, na.rm = T),
        max(gtfs_obj$calendar$end_date, na.rm = T),
        1
      ),
      weekday = weekday(date)
    )
    
    # gather services by weekdays
    service_ids_weekdays <-
      tidyr::gather(
        gtfs_obj$calendar,
        key = "weekday",
        value = "bool",
        -c(service_id, start_date, end_date)
      ) %>%
      dplyr::filter(bool == 1) %>% dplyr::select(-bool)
    
    # set services to dates according to weekdays and start/end date
    date_service_df <- 
      dplyr::full_join(dates, service_ids_weekdays, 
                       by="weekday") %>% 
      dplyr::filter(date >= start_date & date <= end_date) %>% 
      dplyr::select(-weekday, -start_date, -end_date)
  }
  
  if(!is.null(gtfs_obj$calendar_dates)) {
    # add calendar_dates additions (1)
    additions = gtfs_obj$calendar_dates %>% 
      filter(exception_type == 1) %>% 
      dplyr::select(-exception_type)
    if(nrow(additions) > 0) {
      date_service_df <- dplyr::full_join(date_service_df, 
                                          additions, 
                                          by=c("date", "service_id"))
    }
    
    # remove calendar_dates exceptions (2) 
    exceptions = gtfs_obj$calendar_dates %>% 
      dplyr::filter(exception_type == 2) %>% 
      dplyr::select(-exception_type)
    if(nrow(exceptions) > 0) {
      date_service_df <- dplyr::anti_join(date_service_df, 
                                          exceptions, 
                                          by=c("date", "service_id"))
    }
  }
  
  if(nrow(date_service_df) == 0) {
    warning("No start and end dates defined in feed")
  }
  
  gtfs_obj$.$date_service_table <- date_service_df
  
  return(gtfs_obj)
}

# Function to convert "HH:MM:SS" time strings to seconds.
# readr::parse_time() might be faster but doesn't accept hour values > 24
hhmmss_to_seconds <- function(hhmmss_str) {
  sapply(strsplit(hhmmss_str, ":"), function(Y) {
    sum(as.numeric(Y) * c(3600, 60, 1))
  })
}