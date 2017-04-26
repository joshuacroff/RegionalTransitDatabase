import arcpy
import pickle
arcpy.ImportToolbox("C:/temp/RegionalTransitDatabase/esri_rtd17/public-transit-tools/public-transit-tools-master/interpolate-blank-stop-times/InterpolateBlankStopTimes.tbx")

with open('C:/temp/RegionalTransitDatabase/org_acroynms.pickle', 'rb') as f:
	org_acronyms = pickle.load(f)         

org_acronyms1 = org_acronyms[2:4]

for org in org_acronyms:
	stop_times_file = "C:/temp/RegionalTransitDatabase/data/gtfs/{}/stop_times.txt".format(org)
	stop_times_temp_db = "C:/temp/RegionalTransitDatabase/data/gtfs/{}db".format(org)
	arcpy.transit.PreprocessStopTimes(stop_times_file, stop_times_temp_db)
	arcpy.transit.SimpleInterpolation(stop_times_temp_db, stop_times_file)