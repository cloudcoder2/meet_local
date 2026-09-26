import { z } from "zod";
import { VEHICLE_CLASSES } from "./pricing";

export const latLngSchema = z.object({
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
});

export const placeSchema = latLngSchema.extend({
  address: z.string().trim().min(1).max(200),
});

export const vehicleClassSchema = z.enum(VEHICLE_CLASSES);

export const vehicleSchema = z.object({
  vehicle_class: vehicleClassSchema,
  make: z.string().trim().min(1).max(40),
  model: z.string().trim().min(1).max(40),
  color: z.string().trim().min(1).max(20),
  plate_number: z.string().trim().min(3).max(20).transform((s) => s.toUpperCase()),
});
