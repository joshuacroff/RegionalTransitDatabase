######
##Calculate Frequent Bus Routes
######
#this is the main function and goal of the r scripts here
#todo: 
#document some of the Reduce calls
#collapse the am and pm filtering to one function and call it

#' Get a dataframe of stops and routes that are TPA eligible from a GTFSr object
#' @param gtfs_obj A GTFS (gtfsr) list object with components agency_df, etc.
#' @return a dataframe of stops for TPA eligible bus routes

# get_peak_bus_route_stops <- function(gtfs_obj) {
# }

#' Make a dataframe GTFS arrival_time column into standard time variable
#' @param a GTFSr object for a given provider with routes, stops, stop_times, etc
#' @return a mega-GTFSr data frame with stops, stop_times, trips, calendar, and routes all joined
join_all_gtfs_tables <- function(g) {
  df <- list(g$stops_df,g$stop_times_df,g$trips_df,g$calendar_df,g$routes_df)
  Reduce(inner_join,df) %>%
    select(agency_id, stop_id, trip_id, service_id,
           monday, tuesday, wednesday, thursday, friday,
           route_id, trip_headsign, direction_id,
           arrival_time, stop_sequence,
           route_type, stop_lat, stop_lon) %>%
    arrange(agency_id, trip_id, service_id,
            monday, tuesday, wednesday, thursday, friday,
            route_id, trip_headsign, direction_id,
            arrival_time, stop_sequence) -> df_sr
  #clean up source data
  rm(df)
  df_sr$Route_Pattern_ID<-paste0(df_sr$agency_id,
                                 "-",df_sr$route_id,"-",
                                 df_sr$direction_id)
  return(df_sr)
}


######
##Custom Time Format Functions
######

#' Make a dataframe GTFS arrival_time column into standard time variable
#' @param dataframe containing a GTFS-style "arrival_time" column (time values at +24:00:00)
#' @return dataframe containing a GTFS-style "arrival_time" column (no time values at +24:00:00)
make_arrival_hour_less_than_24 <- function(df) {
  t1 <- df$arrival_time
  if (!(typeof(t1) == "character")) {
    stop("column not a character string--may already be fixed")
  }
  df$arrival_time <- sapply(t1,FUN=fix_hour)
  df$arrival_time <- as.POSIXct(df$arrival_time, format= "%H:%M:%S")
  df
}

#' Format a time string in the expected format
#' @param x a GTFS hour string with an hour greater than 24
#' @param hour_replacement the hour to replace the >24 value with
#' @return a string formatted hh:mm:ss 
format_new_hour_string <- function(x,hour_replacement) {
  xl <- length(unlist(strsplit(x,":")))
  if (xl > 3){
    stop("unexpected time string")
  }
  minute <- as.integer(unlist(strsplit(x,":"))[[2]])
  second <- as.integer(unlist(strsplit(x,":"))[[3]])
  x <- paste(c(hour_replacement,minute,second),collapse=":")
  return(x)
}

#' Make a dataframe GTFS arrival_time column into standard time variable
#' @param dataframe containing a GTFS-style "arrival_time" column (time values at +24:00:00)
#' @return dataframe containing a GTFS-style "arrival_time" column (all time values at +24:00:00 set below 24)
fix_hour <- function(x) {
  # use:
  #   t1 <- stop_times$arrival_time
  #   stop_times$arrival_time <- sapply(t1,FUN=fix_hour)
  if(!is.na(x)) {
    hour <- as.integer(unlist(strsplit(x,":"))[[1]])
    if(!is.na(hour) & hour > 23) {
      hour <- hour-24
      x <- format_new_hour_string(x, hour)
      if (hour > 47){
        stop("hour is greater than 47 in stop times")
      }
    }
  }
  x
}

######
##Custom Bus Frequency Functions
######

#' Filter a mega-GTFSr dataframe to rows/stops that occur on all weekdays, are buses, and
#' have a stop_time between 2 time periods
#' @param a mega-GTFSr dataframe made with the join_all_gtfs_tables() function
#' @param period - "AM" or "PM"
#' @return a mega-GTFSr dataframe filtered to TPA peak periods and flagged as AM or PM peak
flag_and_filter_peak_periods_by_time <- function(mega_df, period) {
  if (period=="AM"){
    time_start <- "06:00:00"
    time_end <- "09:59:00"
  } else {
    time_start <- "15:00:00"
    time_end <- "18:59:00"
  }
  
  mega_df <- filter_by_time(mega_df,
                                  time_start,
                                  time_end)
  
  if (!(is.data.frame(mega_df) && nrow(mega_df)==0) && period=="AM"){
    mega_df["Peak_Period"] <-"AM Peak"
  } else if (!(is.data.frame(mega_df) && nrow(mega_df)==0) && period=="PM" ) {
    mega_df["Peak_Period"] <-"PM Peak" 
  } else
  {
  mega_df$Peak_Period <-  mega_df$route_id
  }
  return(mega_df)
}

#' Filter a mega-GTFSr dataframe to rows/stops that occur on all weekdays, are buses, and
#' have a stop_time between 2 time periods
#' @param a dataframe made by joining all the GTFS tables together
#' @param a start time filter hh:mm:ss
#' @param an end time filter hh:mm:ss
#' @return a mega-GTFSr dataframe filtered to rows of interest
filter_by_time <- function(rt_df, start_filter,end_filter) {
  time_start <- paste(c(format(Sys.Date(), "%Y-%m-%d"),
                        start_filter),collapse=" ")
  time_end <- paste(c(format(Sys.Date(), "%Y-%m-%d"),
                      end_filter),collapse=" ")
  rt_df_out <- subset(rt_df, rt_df$monday == 1
                           & rt_df$tuesday == 1
                           & rt_df$wednesday == 1
                           & rt_df$thursday == 1
                           & rt_df$friday == 1
                           & rt_df$route_type == 3
                           & rt_df$arrival_time >time_start
                           & rt_df$arrival_time < time_end)
  return(rt_df_out)
}

#' for a mega-GTFSr dataframe, remove rows with duplicate stop times 
#' @param a dataframe of stops with a stop_times column 
#' @return a dataframe of stops with a stop_times column in which there are no duplicate stop times for a given stop
remove_duplicate_stops <- function(rt_df){
  rt_df %>%
    distinct(agency_id, route_id, direction_id,
             trip_headsign, stop_id, stop_sequence, arrival_time, Peak_Period) %>%
    arrange(agency_id, route_id, direction_id,
            arrival_time,stop_sequence)->rt_df_out
  return(rt_df_out)
}

#' for a mega-GTFSr dataframe, count the number of trips a bus takes through a given stop within a given time period
#' @param a mega-GTFSr dataframe
#' @return a dataframe of stops with a "Trips" variable representing the count trips taken through each stop for a route within a given time frame
count_trips<- function(rt_df) {
  rt_df_out <- rt_df %>%
    group_by(agency_id,
             route_id,
             direction_id,
             trip_headsign,
             stop_id,
             Peak_Period) %>%
    count(stop_sequence) %>%
    mutate(Headways = round(240/n,0))
  colnames(rt_df_out)[colnames(rt_df_out)=="n"] <- "Trips"
  return(rt_df_out)
}

#' for a mega-GTFSr dataframe, reduce it to just a listing of routes
#' @param a mega-GTFSr dataframe
#' @return a dataframe of routes  
get_routes <- function(rt_df) {
  group_by(rt_df,
           agency_id,
           route_id,
           direction_id,
           trip_headsign,
           Peak_Period) %>%
    mutate(Total_Trips = round(mean(Trips),0),
           Headway = round(mean(Headways),0)) %>%
    distinct(agency_id,
             route_id,
             direction_id,
             trip_headsign,
             Total_Trips,
             Headway) ->
    rt_df_out
}

#' 
#' @param a mega-GTFSr dataframe filtered to AM peak commute period stops
#' @param a mega-GTFSr dataframe filtered to PM peak commute period stops
#' @param a mega-GTFSr get_routes reduced dataframe filtered to AM peak commute period stops
#' @param a mega-GTFSr get_routes reduced dataframe filtered to PM peak commute period stops
#' @return a dataframe of stops/routes flagged as TPA eligible or not
join_high_frequency_routes_to_stops <- function(am_stops,pm_stops,am_routes,pm_routes){
  # Combine Weekday High Frequency Bus Service Data Frames for AM/PM Peak Periods
  df1 <- rbind(am_routes,
               pm_routes)

  # This ID is used for grouping and headway counts 
  #(same name as another id in here but dropped anyway)
  #should probably replace at some point
  if (!(is.data.frame(am_routes) && nrow(am_routes)==0)){
    df1$Route_Pattern_ID<-paste0(df1$agency_id,
                                 "-",df1$route_id,"-",
                                 df1$Peak_Period)
  } else 
  {
    df1$Route_Pattern_ID <-  df1$Peak_Period
  }

  # Count number of routes that operate in both directions during peak periods.
  #TPA_Criteria = 2 or 3 then Route operates in both directions during peak periods
  #TPA Criteria = 1 possible loop route or route only operates in ection during peak periods.

  df2 <- df1 %>%
    group_by(agency_id, route_id, Peak_Period, Route_Pattern_ID) %>%
    summarise(TPA_Criteria = n())

  # 6C. Join Total By Direction with Weekday High Frequency Bus Service tables to flag those routes that meet the criteria.
  df3 <- list(df1,df2)
  df4 <- Reduce(inner_join,df3) %>%
    select(agency_id, route_id, direction_id, trip_headsign,Total_Trips, Headway, Peak_Period, TPA_Criteria) %>%
    arrange(agency_id, route_id, direction_id, Peak_Period)

  # 6D. Update values in TPA Criteria field. 2,3 = Meets Criteria, 1 = Review for Acceptance
  df4$TPA_Criteria[df3$TPA_Criteria==3] <- "Meets TPA Criteria"
  df4$TPA_Criteria[df3$TPA_Criteria==2] <- "Meets TPA Criteria"
  df4$TPA_Criteria[df3$TPA_Criteria==1] <- "Does Not Meet TPA Criteria"
  # 6D-1. Update values in TPA Criteria field.  All Loops in AM/PM Peak periods that have 15 mins or better headways = Meets TPA Criteria
  df4$TPA_Criteria[grepl('loop', df3$trip_headsign, ignore.case = TRUE)] <- "Meets TPA Criteria"

  df5 <- rbind(am_stops,pm_stops)

  # 6G. Join Weekday_Peak_Bus_Routes with df3 to generate a stop schedule for all AM/PM Peak Period stops that have headways of 15 mins. or better.
  df6 <- list(df5,df4)
  df7 <- Reduce(inner_join,df6) %>%
    select(agency_id, route_id, direction_id, trip_headsign, stop_id, stop_sequence, Total_Trips, Headway, Peak_Period, TPA_Criteria)

  return(df7)
}


#' 
#' @param a mega-GTFSr dataframe 
#' @param a mega-GTFSr get_routes reduced dataframe
#' @return a dataframe of stops/routes flagged as TPA eligible, with some of the variables dropped from the stops table above joined back on the table
join_mega_and_hf_routes <- function(df_sr,df_rt_hf){
  df<- list(df_sr,df_rt_hf)
  
  df_stp_rt_hf <- Reduce(inner_join,df) %>%
    group_by(agency_id, route_id, direction_id, trip_id,Peak_Period, Route_Pattern_ID,
             trip_headsign, stop_id, stop_sequence, Total_Trips, Headway, Peak_Period,
             TPA_Criteria, stop_lon, stop_lat) %>%
    select(agency_id, route_id, direction_id, trip_id, Route_Pattern_ID,
           trip_headsign, stop_id, stop_sequence, Total_Trips,
           Headway, Peak_Period, TPA_Criteria,
           stop_lon, stop_lat) %>%
    arrange(agency_id, route_id, direction_id,
            trip_id, Peak_Period, stop_sequence)
  
  rm(df)
  return(df_stp_rt_hf)
}

#` Select Distinct Records based upon Agency Route Direction values.  Removes stop ids from output.
#' @param a dataframe output by join_mega_and_hf_routes()
#' @return a deduplicated version of the input dataframe
deduplicate_final_table <- function(df_stp_rt_hf) {
  df_stp_rt_hf <- group_by(df_stp_rt_hf,
                           agency_id, route_id, direction_id, Route_Pattern_ID,trip_headsign,
                           stop_id, stop_sequence, Total_Trips, Headway, Peak_Period,
                           TPA_Criteria, stop_lon, stop_lat) %>%
    distinct(agency_id, route_id, direction_id, Route_Pattern_ID,
             trip_headsign, stop_id, stop_sequence, Total_Trips,
             Headway, Peak_Period, TPA_Criteria, stop_lon, stop_lat)
  return(df_stp_rt_hf)
}