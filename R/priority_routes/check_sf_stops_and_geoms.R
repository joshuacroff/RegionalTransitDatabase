#be sure to set the project path
PROJECT_PATH <- "C:/projects/RTD/RegionalTransitDatabase"

GTFS_PATH <- paste0(PROJECT_PATH,"/data/05_2017_511_GTFS/",collapse="")
R_HELPER_FUNCTIONS_PATH <- paste0(PROJECT_PATH,"/R/r511.R",collapse="")
source(R_HELPER_FUNCTIONS_PATH)
CREDENTIALS_PATH <- paste0(PROJECT_PATH,"credentials.R",collapse="") 

# if (!require(devtools)) {
#   install.packages('devtools')
# }
# devtools::install_github('MetropolitanTransportationCommission/gtfsr')

library(gtfsr)
library(dplyr)

setwd(GTFS_PATH)

library(rjson)
json_file <- paste0(PROJECT_PATH,"/data/orgs.json",collapse="")
providers <- fromJSON(paste(readLines(json_file), collapse=""))

l_p_hf <- list()
l_p_hf_errors <- list()

################################################
# Section 3. Read a single provider set using GTFSr

for (provider in c("SF")) {
  zip_path <- paste0(provider,".zip",collapse="")
  gtfs_obj <- import_gtfs(zip_path, local=TRUE)
  
  ###############################################
  # Section 4. Join all the GTFS provider tables into 1 table based around stops
  
  df_sr <- join_all_gtfs_tables(gtfs_obj)
  df_sr <- make_arrival_hour_less_than_24(df_sr)
  
  ###########################################################################################
  # Section 5. Create Peak Headway tables for weekday trips 
  
  am_stops <- flag_and_filter_peak_periods_by_time(df_sr,"AM")
  am_stops <- remove_duplicate_stops(am_stops) #todo: see https://github.com/MetropolitanTransportationCommission/RegionalTransitDatabase/issues/31
  am_stops <- count_trips(am_stops) 
  am_stops_hdwy <- subset(am_stops,
                          am_stops$Headways < 16)
  am_routes <- get_routes(am_stops_hdwy)
  
  pm_stops <- flag_and_filter_peak_periods_by_time(df_sr,"PM")
  pm_stops <- remove_duplicate_stops(pm_stops) #todo: see https://github.com/MetropolitanTransportationCommission/RegionalTransitDatabase/issues/31
  pm_stops <- count_trips(pm_stops)
  pm_stops_hdwy <- subset(pm_stops,
                          pm_stops$Headways < 16)
  pm_routes <- get_routes(pm_stops_hdwy)
  
  ###########################################################################################
  # Section 6. Join the calculated am and pm peak routes (tpa eligible) back to stop tables
  
  df_rt_hf <- join_high_frequency_routes_to_stops(am_stops,pm_stops,am_routes,pm_routes)
  # 
  # ###########################################################################################
  # # Section 7. Join original stops mega-GTFSr data frame to Selected Routes for export to solve routes in Network Analyst
  # 
  df_stp_rt_hf <- join_mega_and_hf_routes(df_sr, df_rt_hf)

  df_stp_rt_hf <- deduplicate_final_table(df_stp_rt_hf)

  #Remove select cols.
  df_stp_rt_hf <- df_stp_rt_hf[-c(1:13)]
  # 
  ##############
  #get route geometries and write to disk
  ###############
  
  if (dim(am_routes)[1] > 0 & dim(pm_routes)[1] > 0) {
    df1 <- rbind(am_routes,
                 pm_routes)
    l2 <- get_hf_geoms(df1,gtfs_obj,df_stp_rt_hf)
    
    library(rgeos)
    library(reshape2)
    hf_gm_df_ri <- route_id_indexed_sldf(l2,df1)
    
    l_p_hf[provider] <- hf_gm_df_ri
  } else
  {
    l_p_hf_errors[provider] <- df_sr
  }
  #writeOGR(df_sp$gtfslines,"Sf_geoms3.csv",driver="CSV",layer = "sf",dataset_options = c("GEOMETRY=AS_WKT"))
}

#bind all the results together and add an agency_id name
spdfout <- l_p_hf[[1]]
spdfout$agency <- names(l_p_hf[1])

dfx <- as.data.frame(df_stp_rt_hf)
coordinates(dfx) = ~stop_lon + stop_lat

library(rgdal)
proj4string(dfx) <- CRS("+proj=longlat +datum=WGS84")
writeOGR(dfx,"sf_stops3.gpkg",driver="GPKG",layer = "sf_stops", overwrite_layer = TRUE)
proj4string(spdfout) <- CRS("+proj=longlat +datum=WGS84")
writeOGR(spdfout,"sf_routes3.gpkg",driver="GPKG",layer = "sf_routes", overwrite_layer = TRUE)

spdfout_26910 <- spTransform(spdfout, CRS("+init=epsg:26910"))
writeOGR(spdfout_26910,"hf_bus_routes_26910.gpkg",driver="GPKG",layer = "hfbus_routes_26910", overwrite_layer = TRUE)



