/* MySQL dataset type: Load zone and IP data from MySQL database */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <syslog.h>
#include <mysql/mysql.h>
#include "rbldnsd.h"

/* Forward declaration */
struct zone *addzone(struct zone *zonelist, const char *spec);

struct mysql_entry {
  char ip[46];           /* IPv4 or IPv6 address */
  char return_code[16];  /* Return value for DNS query */
  struct mysql_entry *next;
};

struct dsdata {
  MYSQL *mysql_conn;     /* MySQL connection */
  char *host;            /* MySQL host */
  char *user;            /* MySQL user */
  char *password;        /* MySQL password */
  char *database;        /* MySQL database */
  char *table;           /* MySQL table */
  char *zone_name;       /* Zone name from database */
  struct mysql_entry *entries;  /* List of IP entries */
  unsigned n_entries;    /* Number of entries */
};

static void ds_mysql_reset(struct dsdata *dsd, int freeall) {
  struct mysql_entry *entry = dsd->entries;
  while (entry) {
    struct mysql_entry *next = entry->next;
    free(entry);
    entry = next;
  }
  dsd->entries = NULL;
  dsd->n_entries = 0;
  
  if (dsd->mysql_conn) {
    mysql_close(dsd->mysql_conn);
    dsd->mysql_conn = NULL;
  }
  
  if (freeall) {
    free(dsd->host);
    free(dsd->user);
    free(dsd->password);
    free(dsd->database);
    free(dsd->table);
    free(dsd->zone_name);
  }
}

static int ds_mysql_parse_config(const char *config, struct dsdata *dsd) {
  /* Hardcoded MySQL configuration */
  dsd->host = strdup("localhost");
  dsd->user = strdup("root");
  dsd->password = strdup("");
  dsd->database = strdup("rbl_db");
  dsd->table = strdup("rbl_ips");
  dsd->zone_name = strdup(config); /* Use the config as zone name */
  
  return 1;
}

static int ds_mysql_connect(struct dsdata *dsd) {
  dsd->mysql_conn = mysql_init(NULL);
  if (!dsd->mysql_conn) return 0;
  
  if (!mysql_real_connect(dsd->mysql_conn, dsd->host, dsd->user, 
                         dsd->password, dsd->database, 0, NULL, 0)) {
    mysql_close(dsd->mysql_conn);
    dsd->mysql_conn = NULL;
    return 0;
  }
  
  return 1;
}

/* Helper function to reverse IP address for RBL format */
static void reverse_ip(const char *original_ip, char *reversed_ip, size_t size) {
  int a, b, c, d;
  if (sscanf(original_ip, "%d.%d.%d.%d", &a, &b, &c, &d) == 4) {
    snprintf(reversed_ip, size, "%d.%d.%d.%d", d, c, b, a);
  } else {
    strncpy(reversed_ip, original_ip, size - 1);
    reversed_ip[size - 1] = '\0';
  }
}

static int ds_mysql_load_data(struct dataset UNUSED *ds, struct dsdata *dsd) {
  MYSQL_RES *result;
  MYSQL_ROW row;
  char query[512];
  
  printf("DEBUG: Loading data from MySQL database for zone: %s\n", dsd->zone_name);
  fflush(stdout);
  
  /* Query IPs for this specific zone */
  snprintf(query, sizeof(query), 
           "SELECT ip, return_code FROM rbl_ips WHERE zone = '%s'", 
           dsd->zone_name);
  
  if (mysql_query(dsd->mysql_conn, query) != 0) {
    printf("DEBUG: MySQL query failed: %s\n", mysql_error(dsd->mysql_conn));
    fflush(stdout);
    return 0;
  }
  
  result = mysql_store_result(dsd->mysql_conn);
  if (!result) {
    printf("DEBUG: MySQL store result failed: %s\n", mysql_error(dsd->mysql_conn));
    fflush(stdout);
    return 0;
  }
  
  printf("DEBUG: Found %llu rows for zone %s\n", (unsigned long long)mysql_num_rows(result), dsd->zone_name);
  fflush(stdout);
  
  /* Process each row from the database */
  while ((row = mysql_fetch_row(result))) {
    if (row[0] && row[1]) {  /* ip and return_code are not NULL */
      struct mysql_entry *entry = malloc(sizeof(struct mysql_entry));
      if (!entry) continue;
      
      /* Store IP as-is (dntoip already gives us the reversed format) */
      strncpy(entry->ip, row[0], sizeof(entry->ip) - 1);
      entry->ip[sizeof(entry->ip) - 1] = '\0';
      
      strncpy(entry->return_code, row[1], sizeof(entry->return_code) - 1);
      entry->return_code[sizeof(entry->return_code) - 1] = '\0';
      
      entry->next = dsd->entries;
      dsd->entries = entry;
      dsd->n_entries++;
      
      printf("DEBUG: Added DB entry: %s (from %s) -> %s\n", 
             entry->ip, row[0], entry->return_code);
      fflush(stdout);
    }
  }
  
  mysql_free_result(result);
  
  printf("DEBUG: Loaded %d entries from database for zone %s\n", dsd->n_entries, dsd->zone_name);
  fflush(stdout);
  
  return 1;
}

/* Function to discover all zones from MySQL database */
int ds_mysql_discover_zones(struct zone **zonelist) {
  MYSQL *mysql_conn;
  MYSQL_RES *result;
  MYSQL_ROW row;
  char query[256];
  char zone_spec[512];
  struct zone *zone;
  
  /* Hardcoded MySQL connection */
  mysql_conn = mysql_init(NULL);
  if (!mysql_conn) return 0;
  
  if (!mysql_real_connect(mysql_conn, "localhost", "root", "", "rbl_db", 0, NULL, 0)) {
    mysql_close(mysql_conn);
    return 0;
  }
  
  /* Get all unique zones from database */
  snprintf(query, sizeof(query), "SELECT DISTINCT zone FROM rbl_ips");
  
  if (mysql_query(mysql_conn, query) != 0) {
    mysql_close(mysql_conn);
    return 0;
  }
  
  result = mysql_store_result(mysql_conn);
  if (!result) {
    mysql_close(mysql_conn);
    return 0;
  }
  
  /* Create zones for each zone found in database */
  while ((row = mysql_fetch_row(result))) {
    if (row[0]) {
      /* Create zone specification: zone:mysql:zone_name */
      snprintf(zone_spec, sizeof(zone_spec), "%s:mysql:%s", row[0], row[0]);
      
      printf("DEBUG: Creating zone: %s\n", zone_spec);
      fflush(stdout);
      
      /* Add zone using existing addzone function */
      zone = addzone(*zonelist, zone_spec);
      if (zone) {
        *zonelist = zone;
        printf("DEBUG: Zone created successfully: %s\n", row[0]);
        printf("DEBUG: Zone has %d datasets\n", zone->z_dsl ? 1 : 0);
        fflush(stdout);
      } else {
        printf("DEBUG: Failed to create zone: %s\n", row[0]);
        fflush(stdout);
      }
    }
  }
  
  mysql_free_result(result);
  mysql_close(mysql_conn);
  return 1;
}

static void ds_mysql_start(struct dataset *ds) {
  struct dsdata *dsd = ds->ds_dsd;
  
  printf("DEBUG: ds_mysql_start called for spec: %s\n", ds->ds_spec);
  fflush(stdout);
  
  /* Parse configuration directly from ds_spec */
  if (!ds_mysql_parse_config(ds->ds_spec, dsd)) {
    printf("DEBUG: Failed to parse MySQL configuration\n");
    fflush(stdout);
    dslog(LOG_ERR, NULL, "Failed to parse MySQL configuration");
    return;
  }
  
  printf("DEBUG: MySQL config parsed, connecting...\n");
  fflush(stdout);
  
  if (!ds_mysql_connect(dsd)) {
    printf("DEBUG: Failed to connect to MySQL database\n");
    fflush(stdout);
    dslog(LOG_ERR, NULL, "Failed to connect to MySQL database");
    return;
  }
  
  printf("DEBUG: MySQL connected, loading data...\n");
  fflush(stdout);
  
  if (!ds_mysql_load_data(ds, dsd)) {
    printf("DEBUG: Failed to load data from MySQL\n");
    fflush(stdout);
    dslog(LOG_ERR, NULL, "Failed to load data from MySQL");
    return;
  }
  
  printf("DEBUG: MySQL data loaded successfully, %d entries\n", dsd->n_entries);
  fflush(stdout);
}

static int ds_mysql_line(struct dataset UNUSED *ds, char UNUSED *s, 
                        struct dsctx UNUSED *dsc) {
  /* No line-by-line processing for MySQL */
  return 1;
}

static void ds_mysql_finish(struct dataset *ds, struct dsctx *dsc) {
  struct dsdata *dsd = ds->ds_dsd;
  dsloaded(dsc, "mysql entries=%u", dsd->n_entries);
}

static int ds_mysql_query(const struct dataset *ds, const struct dnsqinfo *qi,
                          struct dnspacket *pkt) {
  const struct dsdata *dsd = ds->ds_dsd;
  const struct mysql_entry *entry;
  char query_ip[46];
  
  printf("DEBUG: ds_mysql_query called\n");
  fflush(stdout);
  
  /* Convert query IP to string */
  if (qi->qi_ip4valid) {
    snprintf(query_ip, sizeof(query_ip), "%s", ip4atos(qi->qi_ip4));
  } else if (qi->qi_ip6valid) {
    snprintf(query_ip, sizeof(query_ip), "%s", ip6atos(qi->qi_ip6, IP6ADDR_FULL));
  } else {
    printf("DEBUG: No valid IP in query\n");
    fflush(stdout);
    return 0;
  }
  
  printf("DEBUG: Querying IP: %s\n", query_ip);
  fflush(stdout);
  
  /* Search for IP in our list */
  for (entry = dsd->entries; entry; entry = entry->next) {
    printf("DEBUG: Checking against: %s\n", entry->ip);
    fflush(stdout);
    if (strcmp(entry->ip, query_ip) == 0) {
      /* Found the IP, return the specified value */
      printf("DEBUG: Found match! Returning: %s\n", entry->return_code);
      fflush(stdout);
      
      /* Format return code for addrr_a_txt: 4 bytes IP + text */
      char rr_data[4 + 256];
      ip4addr_t return_ip;
      
      /* Parse return code as IP address */
      if (ip4addr(entry->return_code, &return_ip, NULL) > 0) {
        PACK32(rr_data, return_ip);  /* First 4 bytes: IP in network byte order */
        strcpy(rr_data + 4, entry->return_code);  /* Text after IP */
        
        addrr_a_txt(pkt, qi->qi_tflag, rr_data, query_ip, ds);
        return NSQUERY_FOUND;
      } else {
        printf("DEBUG: Invalid return code format: %s\n", entry->return_code);
        fflush(stdout);
      }
    }
  }
  
  printf("DEBUG: No match found for %s\n", query_ip);
  fflush(stdout);
  return 0; /* Not found */
}

static void ds_mysql_dump(const struct dataset *ds, 
                         const unsigned char UNUSED *odn, FILE *f) {
  const struct dsdata *dsd = ds->ds_dsd;
  const struct mysql_entry *entry;
  
  fprintf(f, "; MySQL dataset dump\n");
  for (entry = dsd->entries; entry; entry = entry->next) {
    fprintf(f, "%s %s\n", entry->ip, entry->return_code);
  }
}

definedstype(mysql, DSTF_IP4REV|DSTF_IP6REV, "MySQL database with IP addresses");