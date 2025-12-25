/**
 * Beautiful Colorful 3D Christmas Tree - Wayland Window Manager
 * This C wrapper handles Wayland protocol communication and displays
 * the rendered Christmas tree from our assembly code.
 * 
 * Author: Antigravity AI
 * Date: December 25, 2025
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>
#include <wayland-client.h>
#include <linux/input.h>
#include <time.h>
#include <math.h>
#include <fcntl.h>
#include <sys/stat.h>

/* Include XDG shell protocol header */
#include "xdg-shell-client-protocol.h"

/* Window dimensions */
#define WIDTH 800
#define HEIGHT 600
#define STRIDE (WIDTH * 4)
#define BUFFER_SIZE (WIDTH * HEIGHT * 4)

/* Wayland globals */
static struct wl_display *display = NULL;
static struct wl_registry *registry = NULL;
static struct wl_compositor *compositor = NULL;
static struct wl_shm *shm = NULL;
static struct xdg_wm_base *xdg_wm_base = NULL;
static struct wl_surface *surface = NULL;
static struct xdg_surface *xdg_surface = NULL;
static struct xdg_toplevel *xdg_toplevel = NULL;
static struct wl_buffer *buffer = NULL;
static uint32_t *shm_data = NULL;
static int running = 1;
static int configured = 0;

/* Animation state */
static uint32_t frame_count = 0;
static double random_seed = 12345.6789;

/* Snowflake structure */
typedef struct {
    float x, y;
    float speed;
    float drift;
    int size;
} Snowflake;

#define MAX_SNOWFLAKES 80
static Snowflake snowflakes[MAX_SNOWFLAKES];

/* Light structure */
typedef struct {
    int x, y;
    int radius;
    uint32_t color;
    int phase;
} TreeLight;

#define MAX_LIGHTS 50
static TreeLight lights[MAX_LIGHTS];

/* Ornament structure */
typedef struct {
    int x, y;
    int radius;
    uint32_t color;
    float shine_angle;
} Ornament;

#define MAX_ORNAMENTS 15
static Ornament ornaments[MAX_ORNAMENTS];

/* Color palette */
static const uint32_t ORNAMENT_COLORS[] = {
    0xFFFF1744,  /* Vibrant Red */
    0xFFFFD700,  /* Gold */
    0xFF2979FF,  /* Electric Blue */
    0xFFE040FB,  /* Purple */
    0xFF00E5FF,  /* Cyan */
    0xFFFF9100,  /* Orange */
    0xFFFFFFFF,  /* White */
    0xFF69F0AE,  /* Mint Green */
    0xFFFF4081,  /* Pink */
    0xFF7C4DFF,  /* Deep Purple */
};
#define NUM_ORNAMENT_COLORS (sizeof(ORNAMENT_COLORS) / sizeof(ORNAMENT_COLORS[0]))

/* Fast pseudo-random number generator */
static double fast_random(void) {
    random_seed = random_seed * 1103515245.0 + 12345.0;
    random_seed = fmod(random_seed, 2147483648.0);
    return random_seed / 2147483648.0;
}

static int random_int(int min, int max) {
    return min + (int)(fast_random() * (max - min + 1));
}

/* Color manipulation functions */
static uint32_t blend_colors(uint32_t c1, uint32_t c2, float ratio) {
    uint8_t r1 = (c1 >> 16) & 0xFF;
    uint8_t g1 = (c1 >> 8) & 0xFF;
    uint8_t b1 = c1 & 0xFF;
    
    uint8_t r2 = (c2 >> 16) & 0xFF;
    uint8_t g2 = (c2 >> 8) & 0xFF;
    uint8_t b2 = c2 & 0xFF;
    
    uint8_t r = (uint8_t)(r1 * (1 - ratio) + r2 * ratio);
    uint8_t g = (uint8_t)(g1 * (1 - ratio) + g2 * ratio);
    uint8_t b = (uint8_t)(b1 * (1 - ratio) + b2 * ratio);
    
    return 0xFF000000 | (r << 16) | (g << 8) | b;
}

static uint32_t brighten_color(uint32_t color, float factor) {
    uint8_t r = (color >> 16) & 0xFF;
    uint8_t g = (color >> 8) & 0xFF;
    uint8_t b = color & 0xFF;
    
    r = (uint8_t)fmin(255, r * factor);
    g = (uint8_t)fmin(255, g * factor);
    b = (uint8_t)fmin(255, b * factor);
    
    return 0xFF000000 | (r << 16) | (g << 8) | b;
}

static uint32_t darken_color(uint32_t color, float factor) {
    uint8_t r = (color >> 16) & 0xFF;
    uint8_t g = (color >> 8) & 0xFF;
    uint8_t b = color & 0xFF;
    
    r = (uint8_t)(r * factor);
    g = (uint8_t)(g * factor);
    b = (uint8_t)(b * factor);
    
    return 0xFF000000 | (r << 16) | (g << 8) | b;
}

/* Initialize snowflakes */
static void init_snowflakes(void) {
    for (int i = 0; i < MAX_SNOWFLAKES; i++) {
        snowflakes[i].x = fast_random() * WIDTH;
        snowflakes[i].y = fast_random() * HEIGHT;
        snowflakes[i].speed = 1.0f + fast_random() * 2.0f;
        snowflakes[i].drift = (fast_random() - 0.5f) * 0.5f;
        snowflakes[i].size = 1 + (int)(fast_random() * 3);
    }
}

/* Initialize tree lights */
static void init_lights(void) {
    for (int i = 0; i < MAX_LIGHTS; i++) {
        /* Position lights within tree shape */
        float t = fast_random();  /* 0 to 1 from top to bottom */
        int y_pos = 130 + (int)(t * 350);
        
        /* Width increases with y */
        int max_width = (int)(t * 180);
        int x_offset = random_int(-max_width, max_width);
        
        lights[i].x = 400 + x_offset;
        lights[i].y = y_pos;
        lights[i].radius = 3 + (int)(fast_random() * 4);
        lights[i].color = ORNAMENT_COLORS[i % NUM_ORNAMENT_COLORS];
        lights[i].phase = random_int(0, 100);
    }
}

/* Initialize ornaments */
static void init_ornaments(void) {
    /* Predefined ornament positions for balanced look */
    int positions[][2] = {
        {400, 180}, {360, 230}, {440, 230},
        {330, 290}, {400, 280}, {470, 290},
        {310, 360}, {370, 350}, {430, 350}, {490, 360},
        {290, 430}, {350, 420}, {400, 430}, {450, 420}, {510, 430}
    };
    
    for (int i = 0; i < MAX_ORNAMENTS; i++) {
        ornaments[i].x = positions[i][0];
        ornaments[i].y = positions[i][1];
        ornaments[i].radius = 8 + random_int(0, 4);
        ornaments[i].color = ORNAMENT_COLORS[i % NUM_ORNAMENT_COLORS];
        ornaments[i].shine_angle = fast_random() * M_PI * 2;
    }
}

/* Draw a single pixel with bounds checking */
static inline void put_pixel(int x, int y, uint32_t color) {
    if (x >= 0 && x < WIDTH && y >= 0 && y < HEIGHT) {
        shm_data[y * WIDTH + x] = color;
    }
}

/* Draw a horizontal gradient line */
static void draw_hline_gradient(int y, int x1, int x2, uint32_t c1, uint32_t c2) {
    if (y < 0 || y >= HEIGHT) return;
    if (x1 > x2) { int t = x1; x1 = x2; x2 = t; }
    if (x1 < 0) x1 = 0;
    if (x2 >= WIDTH) x2 = WIDTH - 1;
    
    int width = x2 - x1;
    if (width <= 0) return;
    
    for (int x = x1; x <= x2; x++) {
        float ratio = (float)(x - x1) / width;
        shm_data[y * WIDTH + x] = blend_colors(c1, c2, ratio);
    }
}

/* Draw filled circle with 3D shading */
static void draw_3d_sphere(int cx, int cy, int radius, uint32_t base_color) {
    for (int dy = -radius; dy <= radius; dy++) {
        for (int dx = -radius; dx <= radius; dx++) {
            float dist = sqrtf(dx * dx + dy * dy);
            if (dist <= radius) {
                /* 3D shading - light from top-left */
                float nx = dx / (float)radius;
                float ny = dy / (float)radius;
                float nz = sqrtf(fmax(0, 1 - nx*nx - ny*ny));
                
                /* Light direction */
                float lx = -0.5f, ly = -0.5f, lz = 0.7f;
                float len = sqrtf(lx*lx + ly*ly + lz*lz);
                lx /= len; ly /= len; lz /= len;
                
                float diffuse = fmax(0, nx*lx + ny*ly + nz*lz);
                float specular = powf(fmax(0, nz), 20) * 0.5f;
                
                /* Edge darkening */
                float edge = 1.0f - dist / radius;
                edge = powf(edge, 0.3f);
                
                float brightness = 0.3f + diffuse * 0.5f + specular;
                brightness *= edge;
                
                uint32_t color;
                if (specular > 0.3f) {
                    /* Specular highlight */
                    color = blend_colors(base_color, 0xFFFFFFFF, specular);
                } else {
                    color = brighten_color(base_color, brightness + 0.5f);
                }
                
                put_pixel(cx + dx, cy + dy, color);
            }
        }
    }
}

/* Draw glowing light */
static void draw_glow(int cx, int cy, int radius, uint32_t color, float intensity) {
    int glow_radius = radius * 3;
    for (int dy = -glow_radius; dy <= glow_radius; dy++) {
        for (int dx = -glow_radius; dx <= glow_radius; dx++) {
            float dist = sqrtf(dx * dx + dy * dy);
            if (dist <= glow_radius) {
                int x = cx + dx;
                int y = cy + dy;
                if (x >= 0 && x < WIDTH && y >= 0 && y < HEIGHT) {
                    float glow = 1.0f - dist / glow_radius;
                    glow = powf(glow, 2) * intensity;
                    
                    if (glow > 0.05f) {
                        uint32_t existing = shm_data[y * WIDTH + x];
                        shm_data[y * WIDTH + x] = blend_colors(existing, color, glow);
                    }
                }
            }
        }
    }
}

/* Render gradient night sky with stars */
static void render_sky(void) {
    uint32_t sky_top = 0xFF0a0a2e;      /* Dark blue */
    uint32_t sky_bottom = 0xFF1a1a4e;   /* Lighter blue */
    
    for (int y = 0; y < HEIGHT; y++) {
        float ratio = (float)y / HEIGHT;
        uint32_t color = blend_colors(sky_top, sky_bottom, ratio);
        for (int x = 0; x < WIDTH; x++) {
            shm_data[y * WIDTH + x] = color;
        }
    }
    
    /* Add twinkling stars */
    srand(42);  /* Fixed seed for consistent star positions */
    for (int i = 0; i < 100; i++) {
        int x = rand() % WIDTH;
        int y = rand() % (HEIGHT / 2);
        
        /* Twinkle based on frame */
        float twinkle = sinf(frame_count * 0.1f + i * 0.5f) * 0.5f + 0.5f;
        uint32_t brightness = (uint32_t)(200 + 55 * twinkle);
        uint32_t color = 0xFF000000 | (brightness << 16) | (brightness << 8) | brightness;
        
        put_pixel(x, y, color);
        if (twinkle > 0.7f) {
            /* Larger star */
            put_pixel(x - 1, y, darken_color(color, 0.5f));
            put_pixel(x + 1, y, darken_color(color, 0.5f));
            put_pixel(x, y - 1, darken_color(color, 0.5f));
            put_pixel(x, y + 1, darken_color(color, 0.5f));
        }
    }
}

/* Render snow-covered ground */
static void render_ground(void) {
    uint32_t snow_white = 0xFFF0F8FF;   /* Snow white */
    uint32_t snow_shadow = 0xFFD0E0F0;  /* Slight blue shadow */
    
    for (int y = 520; y < HEIGHT; y++) {
        for (int x = 0; x < WIDTH; x++) {
            /* Add texture variation */
            float noise = fast_random() * 0.1f;
            float height_factor = (float)(y - 520) / (HEIGHT - 520);
            uint32_t color = blend_colors(snow_white, snow_shadow, height_factor * 0.3f + noise);
            shm_data[y * WIDTH + x] = color;
        }
    }
}

/* Render the 3D Christmas tree */
static void render_tree(void) {
    int center_x = 400;
    int base_y = 520;
    
    /* Tree colors with 3D shading */
    uint32_t tree_dark = 0xFF0d5016;
    uint32_t tree_light = 0xFF1a8a2e;
    uint32_t tree_highlight = 0xFF2ecc40;
    
    /* Draw multiple overlapping triangle layers */
    struct {
        int top_y, bottom_y, width;
    } layers[] = {
        {120, 250, 70},
        {180, 330, 110},
        {260, 410, 150},
        {340, 500, 190}
    };
    
    for (int l = 0; l < 4; l++) {
        int top_y = layers[l].top_y;
        int bottom_y = layers[l].bottom_y;
        int half_width = layers[l].width;
        int height = bottom_y - top_y;
        
        for (int y = top_y; y < bottom_y; y++) {
            if (y < 0 || y >= HEIGHT) continue;
            
            float t = (float)(y - top_y) / height;
            int width_at_y = (int)(t * half_width);
            
            for (int dx = -width_at_y; dx <= width_at_y; dx++) {
                int x = center_x + dx;
                if (x < 0 || x >= WIDTH) continue;
                
                /* 3D shading - left side darker, right side lighter */
                float shade = (float)dx / width_at_y;  /* -1 to 1 */
                shade = (shade + 1) / 2;  /* 0 to 1 */
                
                /* Add vertical gradient */
                float v_shade = 1.0f - t * 0.3f;
                
                uint32_t color;
                if (shade < 0.3f) {
                    color = darken_color(tree_dark, 0.7f + shade);
                } else if (shade > 0.7f) {
                    color = blend_colors(tree_light, tree_highlight, (shade - 0.7f) * 2);
                } else {
                    color = blend_colors(tree_dark, tree_light, shade);
                }
                
                color = brighten_color(color, v_shade);
                
                /* Add some texture/noise */
                if (fast_random() > 0.95f) {
                    color = darken_color(color, 0.8f);
                }
                
                shm_data[y * WIDTH + x] = color;
            }
        }
        
        /* Add "snow" on layer edges */
        int snow_y = top_y + 10;
        int snow_width = (int)(0.08f * half_width);
        for (int dx = -snow_width; dx <= snow_width; dx++) {
            for (int dy = 0; dy < 8; dy++) {
                int x = center_x + dx;
                int y = snow_y + dy;
                float dist = sqrtf(dx * dx + dy * dy);
                if (dist < 10) {
                    uint32_t snow = blend_colors(shm_data[y * WIDTH + x], 0xFFFFFFFF, 0.6f - dist * 0.05f);
                    put_pixel(x, y, snow);
                }
            }
        }
    }
    
    /* Draw trunk */
    uint32_t trunk_dark = 0xFF3d2817;
    uint32_t trunk_light = 0xFF5d4027;
    
    for (int y = 480; y < 530; y++) {
        for (int dx = -25; dx <= 25; dx++) {
            int x = center_x + dx;
            /* 3D cylindrical shading */
            float shade = 1.0f - fabsf((float)dx / 25);
            shade = powf(shade, 0.5f);
            
            uint32_t color = blend_colors(trunk_dark, trunk_light, shade);
            
            /* Add wood grain texture */
            if ((y + (int)(fast_random() * 3)) % 5 == 0) {
                color = darken_color(color, 0.9f);
            }
            
            put_pixel(x, y, color);
        }
    }
}

/* Render golden star on top */
static void render_star(void) {
    int cx = 400, cy = 95;
    
    /* Animated glow */
    float pulse = sinf(frame_count * 0.15f) * 0.3f + 0.7f;
    
    /* Draw outer glow first */
    draw_glow(cx, cy, 20, 0xFFFFD700, pulse * 0.8f);
    
    /* Draw 5-pointed star */
    uint32_t star_color = 0xFFFFD700;
    uint32_t star_bright = 0xFFFFFF00;
    
    for (int angle = 0; angle < 5; angle++) {
        float a = (angle * 72 - 90) * M_PI / 180.0f;
        float a2 = ((angle * 72 + 36) - 90) * M_PI / 180.0f;
        
        /* Outer point */
        int ox = cx + (int)(cosf(a) * 25);
        int oy = cy + (int)(sinf(a) * 25);
        
        /* Inner point */
        int ix = cx + (int)(cosf(a2) * 10);
        int iy = cy + (int)(sinf(a2) * 10);
        
        /* Draw lines forming the star (simplified) */
        for (float t = 0; t <= 1; t += 0.02f) {
            int x = cx + (int)((ox - cx) * t);
            int y = cy + (int)((oy - cy) * t);
            
            float brightness = 1.0f - t * 0.3f;
            uint32_t color = blend_colors(star_color, star_bright, brightness * pulse);
            
            put_pixel(x, y, color);
            put_pixel(x - 1, y, color);
            put_pixel(x + 1, y, color);
            put_pixel(x, y - 1, color);
            put_pixel(x, y + 1, color);
        }
    }
    
    /* Star center */
    for (int dy = -8; dy <= 8; dy++) {
        for (int dx = -8; dx <= 8; dx++) {
            float dist = sqrtf(dx * dx + dy * dy);
            if (dist <= 8) {
                float brightness = 1.0f - dist / 8;
                brightness = powf(brightness, 0.5f) * pulse;
                uint32_t color = blend_colors(star_color, 0xFFFFFFFF, brightness);
                put_pixel(cx + dx, cy + dy, color);
            }
        }
    }
}

/* Render ornaments */
static void render_ornaments(void) {
    for (int i = 0; i < MAX_ORNAMENTS; i++) {
        draw_3d_sphere(ornaments[i].x, ornaments[i].y, 
                       ornaments[i].radius, ornaments[i].color);
        
        /* Add hanging string */
        uint32_t string_color = 0xFF444444;
        for (int dy = -15; dy < 0; dy++) {
            float wave = sinf(dy * 0.3f + ornaments[i].x * 0.1f) * 2;
            put_pixel(ornaments[i].x + (int)wave, 
                     ornaments[i].y + dy - ornaments[i].radius, 
                     string_color);
        }
    }
}

/* Render twinkling lights */
static void render_lights(void) {
    for (int i = 0; i < MAX_LIGHTS; i++) {
        /* Calculate if light is "on" or "off" based on time and phase */
        float phase = sinf(frame_count * 0.2f + lights[i].phase * 0.1f);
        
        if (phase > -0.3f) {  /* Light is on */
            float intensity = (phase + 0.3f) / 1.3f;
            intensity = powf(intensity, 0.5f);
            
            /* Draw glow */
            draw_glow(lights[i].x, lights[i].y, 
                     lights[i].radius, lights[i].color, intensity * 0.7f);
            
            /* Draw bright center */
            uint32_t bright_color = blend_colors(lights[i].color, 0xFFFFFFFF, intensity * 0.5f);
            for (int dy = -2; dy <= 2; dy++) {
                for (int dx = -2; dx <= 2; dx++) {
                    float dist = sqrtf(dx * dx + dy * dy);
                    if (dist <= 2) {
                        put_pixel(lights[i].x + dx, lights[i].y + dy, bright_color);
                    }
                }
            }
        }
    }
}

/* Render falling snow */
static void render_snow(void) {
    for (int i = 0; i < MAX_SNOWFLAKES; i++) {
        int x = (int)snowflakes[i].x;
        int y = (int)snowflakes[i].y;
        int size = snowflakes[i].size;
        
        /* Draw snowflake based on size */
        uint32_t snow_color = 0xFFFFFFFF;
        uint32_t snow_dim = 0xFFCCCCCC;
        
        if (size == 1) {
            put_pixel(x, y, snow_color);
        } else if (size == 2) {
            put_pixel(x, y, snow_color);
            put_pixel(x - 1, y, snow_dim);
            put_pixel(x + 1, y, snow_dim);
        } else {
            /* Larger snowflake - star shape */
            put_pixel(x, y, snow_color);
            put_pixel(x - 1, y, snow_color);
            put_pixel(x + 1, y, snow_color);
            put_pixel(x, y - 1, snow_color);
            put_pixel(x, y + 1, snow_color);
            put_pixel(x - 1, y - 1, snow_dim);
            put_pixel(x + 1, y - 1, snow_dim);
            put_pixel(x - 1, y + 1, snow_dim);
            put_pixel(x + 1, y + 1, snow_dim);
        }
    }
}

/* Update animation state */
static void update_animation(void) {
    frame_count++;
    
    /* Update snowflakes */
    for (int i = 0; i < MAX_SNOWFLAKES; i++) {
        snowflakes[i].y += snowflakes[i].speed;
        snowflakes[i].x += snowflakes[i].drift + sinf(snowflakes[i].y * 0.02f) * 0.5f;
        
        /* Wrap around */
        if (snowflakes[i].y > HEIGHT) {
            snowflakes[i].y = -10;
            snowflakes[i].x = fast_random() * WIDTH;
        }
        if (snowflakes[i].x < 0) snowflakes[i].x += WIDTH;
        if (snowflakes[i].x >= WIDTH) snowflakes[i].x -= WIDTH;
    }
}

/* Render complete frame */
static void render_frame(void) {
    render_sky();
    render_ground();
    render_tree();
    render_ornaments();
    render_lights();
    render_star();
    render_snow();
}

/* Wayland registry handler */
static void registry_handler(void *data, struct wl_registry *registry,
                            uint32_t id, const char *interface, uint32_t version) {
    if (strcmp(interface, wl_compositor_interface.name) == 0) {
        compositor = wl_registry_bind(registry, id, &wl_compositor_interface, 4);
    } else if (strcmp(interface, wl_shm_interface.name) == 0) {
        shm = wl_registry_bind(registry, id, &wl_shm_interface, 1);
    } else if (strcmp(interface, xdg_wm_base_interface.name) == 0) {
        xdg_wm_base = wl_registry_bind(registry, id, &xdg_wm_base_interface, 1);
    }
}

static void registry_remover(void *data, struct wl_registry *registry, uint32_t id) {
    /* Handle global removal if needed */
}

static const struct wl_registry_listener registry_listener = {
    registry_handler,
    registry_remover
};

/* XDG WM base ping handler */
static void xdg_wm_base_ping(void *data, struct xdg_wm_base *xdg_wm_base, uint32_t serial) {
    xdg_wm_base_pong(xdg_wm_base, serial);
}

static const struct xdg_wm_base_listener xdg_wm_base_listener = {
    xdg_wm_base_ping
};

/* XDG surface configure handler */
static void xdg_surface_configure(void *data, struct xdg_surface *xdg_surface, uint32_t serial) {
    xdg_surface_ack_configure(xdg_surface, serial);
    configured = 1;
}

static const struct xdg_surface_listener xdg_surface_listener = {
    xdg_surface_configure
};

/* XDG toplevel handlers */
static void xdg_toplevel_configure(void *data, struct xdg_toplevel *toplevel,
                                   int32_t width, int32_t height,
                                   struct wl_array *states) {
    /* Window resized - we ignore for now and keep fixed size */
}

static void xdg_toplevel_close(void *data, struct xdg_toplevel *toplevel) {
    running = 0;
}

static void xdg_toplevel_configure_bounds(void *data, struct xdg_toplevel *toplevel,
                                          int32_t width, int32_t height) {
    /* Bounds suggested by compositor */
}

static void xdg_toplevel_wm_capabilities(void *data, struct xdg_toplevel *toplevel,
                                         struct wl_array *capabilities) {
    /* WM capabilities */
}

static const struct xdg_toplevel_listener xdg_toplevel_listener = {
    xdg_toplevel_configure,
    xdg_toplevel_close,
    xdg_toplevel_configure_bounds,
    xdg_toplevel_wm_capabilities
};

/* Create shared memory buffer */
static int create_shm_buffer(void) {
    int fd = memfd_create("christmas_tree", 0);
    if (fd < 0) {
        perror("memfd_create");
        return -1;
    }
    
    if (ftruncate(fd, BUFFER_SIZE) < 0) {
        perror("ftruncate");
        close(fd);
        return -1;
    }
    
    shm_data = mmap(NULL, BUFFER_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (shm_data == MAP_FAILED) {
        perror("mmap");
        close(fd);
        return -1;
    }
    
    struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, BUFFER_SIZE);
    buffer = wl_shm_pool_create_buffer(pool, 0, WIDTH, HEIGHT, STRIDE, WL_SHM_FORMAT_ARGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);
    
    return 0;
}

/* Frame callback handler */
static void frame_done(void *data, struct wl_callback *callback, uint32_t time);

static const struct wl_callback_listener frame_listener = {
    frame_done
};

static void frame_done(void *data, struct wl_callback *callback, uint32_t time) {
    wl_callback_destroy(callback);
    
    /* Update and render */
    update_animation();
    render_frame();
    
    /* Attach buffer and commit */
    wl_surface_attach(surface, buffer, 0, 0);
    wl_surface_damage(surface, 0, 0, WIDTH, HEIGHT);
    
    /* Request next frame */
    struct wl_callback *cb = wl_surface_frame(surface);
    wl_callback_add_listener(cb, &frame_listener, NULL);
    
    wl_surface_commit(surface);
}

int main(int argc, char *argv[]) {
    printf("🎄 Beautiful 3D Christmas Tree - Wayland Edition 🎄\n");
    printf("    Merry Christmas! Press Ctrl+C or close window to exit.\n\n");
    
    /* Connect to Wayland display */
    display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "Error: Cannot connect to Wayland display.\n");
        fprintf(stderr, "Make sure you're running under a Wayland compositor.\n");
        return 1;
    }
    
    /* Get registry and bind globals */
    registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);
    
    if (!compositor || !shm || !xdg_wm_base) {
        fprintf(stderr, "Error: Missing required Wayland interfaces.\n");
        return 1;
    }
    
    xdg_wm_base_add_listener(xdg_wm_base, &xdg_wm_base_listener, NULL);
    
    /* Create surface */
    surface = wl_compositor_create_surface(compositor);
    xdg_surface = xdg_wm_base_get_xdg_surface(xdg_wm_base, surface);
    xdg_surface_add_listener(xdg_surface, &xdg_surface_listener, NULL);
    
    xdg_toplevel = xdg_surface_get_toplevel(xdg_surface);
    xdg_toplevel_add_listener(xdg_toplevel, &xdg_toplevel_listener, NULL);
    xdg_toplevel_set_title(xdg_toplevel, "🎄 3D Christmas Tree 🎄");
    xdg_toplevel_set_app_id(xdg_toplevel, "christmas-tree");
    
    wl_surface_commit(surface);
    wl_display_roundtrip(display);
    
    /* Create shared memory buffer */
    if (create_shm_buffer() < 0) {
        return 1;
    }
    
    /* Initialize animation elements */
    init_snowflakes();
    init_lights();
    init_ornaments();
    
    /* Initial render */
    render_frame();
    
    /* Attach buffer and commit */
    wl_surface_attach(surface, buffer, 0, 0);
    wl_surface_damage(surface, 0, 0, WIDTH, HEIGHT);
    
    /* Start frame callback loop */
    struct wl_callback *cb = wl_surface_frame(surface);
    wl_callback_add_listener(cb, &frame_listener, NULL);
    
    wl_surface_commit(surface);
    
    /* Main event loop */
    while (running && wl_display_dispatch(display) != -1) {
        /* Events processed in dispatch */
    }
    
    /* Cleanup */
    if (buffer) wl_buffer_destroy(buffer);
    if (xdg_toplevel) xdg_toplevel_destroy(xdg_toplevel);
    if (xdg_surface) xdg_surface_destroy(xdg_surface);
    if (surface) wl_surface_destroy(surface);
    if (shm_data) munmap(shm_data, BUFFER_SIZE);
    wl_display_disconnect(display);
    
    printf("\n🎁 Thanks for watching! Merry Christmas! 🎁\n");
    
    return 0;
}
