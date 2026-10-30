import { ArrowLeftRight, Blocks, Calendar, CalendarOff, ClipboardList, Clock, Droplet, Droplets, Factory, FileCheck, FileText, Fingerprint, Flame, Fuel, HandCoins, HardHat, ListChecks, MapPin, PackageCheck, PackageMinus, PackagePlus, Phone, Receipt, Route, Ruler, Scale, Target, Trash2, Truck, Users, Wallet, Wrench, type LucideIcon } from "lucide-react";

const MAP: Record<string, LucideIcon> = {
  "fuel": Fuel,
  "ruler": Ruler,
  "truck": Truck,
  "droplet": Droplet,
  "droplets": Droplets,
  "calendar": Calendar,
  "factory": Factory,
  "file-check": FileCheck,
  "scale": Scale,
  "route": Route,
  "wrench": Wrench,
  "clock": Clock,
  "clipboard": ClipboardList,
  "package-check": PackageCheck,
  "package-minus": PackageMinus,
  "package-plus": PackagePlus,
  "arrow-left-right": ArrowLeftRight,
  "list-checks": ListChecks,
  "hard-hat": HardHat,
  "users": Users,
  "flame": Flame,
  "blocks": Blocks,
  "trash": Trash2,
  "fingerprint": Fingerprint,
  "calendar-off": CalendarOff,
  "hand-coins": HandCoins,
  "target": Target,
  "phone": Phone,
  "map-pin": MapPin,
  "receipt": Receipt,
  "wallet": Wallet,
};

export function Icon({ name, size = 24 }: { name: string | null; size?: number }) {
  const C = MAP[name ?? ""] ?? FileText;
  return <C size={size} />;
}
