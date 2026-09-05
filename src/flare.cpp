#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <mutex>

#if _WIN32
#include <windows.h>
#include <bcrypt.h>
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/file.h>
#define FFI_PLUGIN_EXPORT
#endif

#include <mutex>
#include <vector>
#include <algorithm>

// Tiny AES-256 implementation
namespace TinyAES {
    static const uint8_t sbox[256] = {
        0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
        0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
        0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
        0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
        0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
        0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
        0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
        0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
        0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
        0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
        0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
        0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
        0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
        0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
        0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
        0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16
    };

    static const uint8_t Rcon[11] = { 0x8d, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36 };

    static void KeyExpansion(uint8_t* RoundKey, const uint8_t* Key) {
        uint32_t i, j, k;
        uint8_t tempa[4];
        for (i = 0; i < 8; ++i) {
            RoundKey[(i * 4) + 0] = Key[(i * 4) + 0]; RoundKey[(i * 4) + 1] = Key[(i * 4) + 1];
            RoundKey[(i * 4) + 2] = Key[(i * 4) + 2]; RoundKey[(i * 4) + 3] = Key[(i * 4) + 3];
        }
        for (i = 8; i < 60; ++i) {
            k = (i - 1) * 4;
            tempa[0] = RoundKey[k + 0]; tempa[1] = RoundKey[k + 1];
            tempa[2] = RoundKey[k + 2]; tempa[3] = RoundKey[k + 3];
            if (i % 8 == 0) {
                uint8_t u8tmp = tempa[0];
                tempa[0] = tempa[1]; tempa[1] = tempa[2]; tempa[2] = tempa[3]; tempa[3] = u8tmp;
                tempa[0] = sbox[tempa[0]]; tempa[1] = sbox[tempa[1]];
                tempa[2] = sbox[tempa[2]]; tempa[3] = sbox[tempa[3]];
                tempa[0] = tempa[0] ^ Rcon[i / 8];
            } else if (i % 8 == 4) {
                tempa[0] = sbox[tempa[0]]; tempa[1] = sbox[tempa[1]];
                tempa[2] = sbox[tempa[2]]; tempa[3] = sbox[tempa[3]];
            }
            RoundKey[i * 4 + 0] = RoundKey[(i - 8) * 4 + 0] ^ tempa[0];
            RoundKey[i * 4 + 1] = RoundKey[(i - 8) * 4 + 1] ^ tempa[1];
            RoundKey[i * 4 + 2] = RoundKey[(i - 8) * 4 + 2] ^ tempa[2];
            RoundKey[i * 4 + 3] = RoundKey[(i - 8) * 4 + 3] ^ tempa[3];
        }
    }

    static void AddRoundKey(uint8_t round, uint8_t (*state)[4], const uint8_t* RoundKey) {
        for (uint8_t i = 0; i < 4; ++i) {
            for (uint8_t j = 0; j < 4; ++j) state[i][j] ^= RoundKey[(round * 16) + (i * 4) + j];
        }
    }

    static void SubBytes(uint8_t (*state)[4]) {
        for (uint8_t i = 0; i < 4; ++i) {
            for (uint8_t j = 0; j < 4; ++j) state[i][j] = sbox[state[i][j]];
        }
    }

    static void ShiftRows(uint8_t (*state)[4]) {
        uint8_t temp;
        temp = state[0][1]; state[0][1] = state[1][1]; state[1][1] = state[2][1]; state[2][1] = state[3][1]; state[3][1] = temp;
        temp = state[0][2]; state[0][2] = state[2][2]; state[2][2] = temp;
        temp = state[1][2]; state[1][2] = state[3][2]; state[3][2] = temp;
        temp = state[0][3]; state[0][3] = state[3][3]; state[3][3] = state[2][3]; state[2][3] = state[1][3]; state[1][3] = temp;
    }

    static uint8_t xtime(uint8_t x) { return ((x << 1) ^ (((x >> 7) & 1) * 0x1b)); }
    static void MixColumns(uint8_t (*state)[4]) {
        uint8_t Tmp, Tm, t;
        for (uint8_t i = 0; i < 4; ++i) {
            t = state[i][0];
            Tmp = state[i][0] ^ state[i][1] ^ state[i][2] ^ state[i][3];
            Tm = state[i][0] ^ state[i][1]; Tm = xtime(Tm); state[i][0] ^= Tm ^ Tmp;
            Tm = state[i][1] ^ state[i][2]; Tm = xtime(Tm); state[i][1] ^= Tm ^ Tmp;
            Tm = state[i][2] ^ state[i][3]; Tm = xtime(Tm); state[i][2] ^= Tm ^ Tmp;
            Tm = state[i][3] ^ t; Tm = xtime(Tm); state[i][3] ^= Tm ^ Tmp;
        }
    }

    static void Cipher(uint8_t (*state)[4], const uint8_t* RoundKey) {
        AddRoundKey(0, state, RoundKey);
        for (uint8_t round = 1; round < 14; ++round) {
            SubBytes(state); ShiftRows(state); MixColumns(state); AddRoundKey(round, state, RoundKey);
        }
        SubBytes(state); ShiftRows(state); AddRoundKey(14, state, RoundKey);
    }
}

class AES256 {
public:
    static void crypt_ctr(unsigned char* data, size_t len, const unsigned char* key, const unsigned char* iv) {
        uint8_t round_key[240];
        TinyAES::KeyExpansion(round_key, key);
        uint8_t counter[16];
        memcpy(counter, iv, 16);
        uint8_t buffer[16];
        size_t i = 0;
        while (i < len) {
            memcpy(buffer, counter, 16);
            TinyAES::Cipher((uint8_t(*)[4])buffer, round_key);
            for (size_t j = 0; j < 16 && i < len; ++j, ++i) data[i] ^= buffer[j];
            for (int j = 15; j >= 0; --j) { if (++counter[j] != 0) break; }
        }
    }
};

static void generate_random(unsigned char* buf, size_t len) {
#if _WIN32
    BCryptGenRandom(NULL, buf, (ULONG)len, BCRYPT_USE_SYSTEM_PREFERRED_RNG);
#else
    int fd = open("/dev/urandom", O_RDONLY);
    if (fd >= 0) { read(fd, buf, len); close(fd); }
#endif
}

const size_t STORAGE_BLOCK_SIZE = 16384;
const size_t MAX_KEY_LEN = 64;
const int B_DEGREE = 64;
const int MAX_SECONDARY_INDEXES = 8;

static uint32_t crc32_table[256];
static bool crc32_table_computed = false;

static void make_crc32_table() {
    for (uint32_t i = 0; i < 256; i++) {
        uint32_t c = i;
        for (int j = 0; j < 8; j++) {
            if (c & 1) c = 0xedb88320L ^ (c >> 1);
            else c = c >> 1;
        }
        crc32_table[i] = c;
    }
    crc32_table_computed = true;
}

static uint32_t calculate_crc32(const unsigned char *buf, size_t len) {
    if (!crc32_table_computed) make_crc32_table();
    uint32_t c = 0xffffffffL;
    for (size_t i = 0; i < len; i++) {
        c = crc32_table[(c ^ buf[i]) & 0xff] ^ (c >> 8);
    }
    return c ^ 0xffffffffL;
}

typedef struct {
    char magic[4];
    uint32_t version;
    uint64_t fileSize;
    uint64_t dataOffset;
    uint64_t rootPage;
    uint64_t nextFreePage;
    uint64_t freeListHead;
    uint64_t secondaryRoots[MAX_SECONDARY_INDEXES];
    char indexNames[MAX_SECONDARY_INDEXES][32];
    uint32_t checksum;
} DBHeader;

typedef struct {
    uint64_t next;
    uint32_t size;
} FreeNode;

typedef struct {
    uint32_t checksum;
    uint32_t isLeaf;
    uint32_t numKeys;
    char keys[2 * B_DEGREE - 1][MAX_KEY_LEN];
    uint64_t values[2 * B_DEGREE - 1];
    uint64_t children[2 * B_DEGREE];
    char padding[STORAGE_BLOCK_SIZE - 12 - (2 * B_DEGREE - 1) * MAX_KEY_LEN - (2 * B_DEGREE - 1) * 8 - (2 * B_DEGREE) * 8];
} BTreeNode;

typedef struct {
    void* data;
    uint64_t mappedSize;
    std::mutex mtx;
    unsigned char encryption_key[32];
    bool use_encryption;
#if _WIN32
    HANDLE hFile;
    HANDLE hMap;
    HANDLE hWal;
#else
    int fd;
    int wal_fd;
#endif
    char wal_path[1024];
} DB;

typedef struct DBIterator {
    DB* db;
    uint64_t root;
    char endKey[MAX_KEY_LEN];
    struct {
        uint64_t pageOffset;
        uint32_t keyIndex;
    } stack[16];
    int stackSize;
} DBIterator;

extern "C" {

static size_t get_system_page_size() {
#if _WIN32
    SYSTEM_INFO si;
    GetSystemInfo(&si);
    return si.dwPageSize;
#else
    return sysconf(_SC_PAGESIZE);
#endif
}

static void* get_ptr(DB* db, uint64_t offset) {
    return (char*)db->data + offset;
}

static BTreeNode* get_node(DB* db, uint64_t offset) {
    return (BTreeNode*)((char*)db->data + offset);
}

static DBHeader* get_header(DB* db) {
    return (DBHeader*)db->data;
}

static void update_header_checksum(DB* db) {
    DBHeader* h = get_header(db);
    h->checksum = 0;
    h->checksum = calculate_crc32((unsigned char*)h, sizeof(DBHeader));
}

static void update_node_checksum(BTreeNode* node) {
    node->checksum = 0;
    node->checksum = calculate_crc32((unsigned char*)node, STORAGE_BLOCK_SIZE);
}

static bool validate_node_checksum(BTreeNode* node) {
    uint32_t stored = node->checksum;
    node->checksum = 0;
    uint32_t calculated = calculate_crc32((unsigned char*)node, STORAGE_BLOCK_SIZE);
    node->checksum = stored;
    return stored == calculated;
}

static void crypt_page(DB* db, uint64_t offset, unsigned char* data, size_t len) {
    if (!db->use_encryption) return;
    unsigned char iv[16] = {0};
    memcpy(iv, &offset, sizeof(uint64_t));
    AES256::crypt_ctr(data, len, db->encryption_key, iv);
}

typedef struct {
    uint32_t magic;
    uint32_t checksum;
    uint64_t offset;
} WALHeader;

static void wal_log_page(DB* db, uint64_t offset) {
    unsigned char buffer[STORAGE_BLOCK_SIZE];
    memcpy(buffer, get_ptr(db, offset), STORAGE_BLOCK_SIZE);
    crypt_page(db, offset, buffer, STORAGE_BLOCK_SIZE);

    WALHeader hdr;
    hdr.magic = 0x57414C47; // 'WALG'
    hdr.offset = offset;
    hdr.checksum = calculate_crc32(buffer, STORAGE_BLOCK_SIZE);

#if _WIN32
    if (db->hWal == INVALID_HANDLE_VALUE) return;
    DWORD written;
    SetFilePointer(db->hWal, 0, NULL, FILE_END);
    WriteFile(db->hWal, &hdr, sizeof(WALHeader), &written, NULL);
    WriteFile(db->hWal, buffer, STORAGE_BLOCK_SIZE, &written, NULL);
#else
    if (db->wal_fd < 0) return;
    lseek(db->wal_fd, 0, SEEK_END);
    write(db->wal_fd, &hdr, sizeof(WALHeader));
    write(db->wal_fd, buffer, STORAGE_BLOCK_SIZE);
#endif
}

static void wal_replay(DB* db) {
#if _WIN32
    if (db->hWal == INVALID_HANDLE_VALUE) return;
    LARGE_INTEGER size; GetFileSizeEx(db->hWal, &size);
    if (size.QuadPart == 0) return;
    SetFilePointer(db->hWal, 0, NULL, FILE_BEGIN);
    WALHeader hdr;
    unsigned char buffer[STORAGE_BLOCK_SIZE];
    DWORD read;
    while (ReadFile(db->hWal, &hdr, sizeof(WALHeader), &read, NULL) && read == sizeof(WALHeader)) {
        if (hdr.magic != 0x57414C47) break;
        if (ReadFile(db->hWal, buffer, STORAGE_BLOCK_SIZE, &read, NULL) && read == STORAGE_BLOCK_SIZE) {
            uint32_t calculated = calculate_crc32(buffer, STORAGE_BLOCK_SIZE);
            if (calculated == hdr.checksum) {
                if (hdr.offset + STORAGE_BLOCK_SIZE <= db->mappedSize) {
                    crypt_page(db, hdr.offset, buffer, STORAGE_BLOCK_SIZE);
                    memcpy(get_ptr(db, hdr.offset), buffer, STORAGE_BLOCK_SIZE);
                }
            }
        }
    }
#else
    if (db->wal_fd < 0) return;
    struct stat st; fstat(db->wal_fd, &st);
    if (st.st_size == 0) return;
    lseek(db->wal_fd, 0, SEEK_SET);
    WALHeader hdr;
    unsigned char buffer[STORAGE_BLOCK_SIZE];
    while (read(db->wal_fd, &hdr, sizeof(WALHeader)) == sizeof(WALHeader)) {
        if (hdr.magic != 0x57414C47) break;
        if (read(db->wal_fd, buffer, STORAGE_BLOCK_SIZE) == STORAGE_BLOCK_SIZE) {
            uint32_t calculated = calculate_crc32(buffer, STORAGE_BLOCK_SIZE);
            if (calculated == hdr.checksum) {
                if (hdr.offset + STORAGE_BLOCK_SIZE <= (uint64_t)db->mappedSize) {
                    crypt_page(db, hdr.offset, buffer, STORAGE_BLOCK_SIZE);
                    memcpy(get_ptr(db, hdr.offset), buffer, STORAGE_BLOCK_SIZE);
                }
            }
        }
    }
#endif
}

static bool db_resize(DB* db, uint64_t newSize) {
    size_t sysPageSize = get_system_page_size();
    newSize = (newSize + sysPageSize - 1) & ~(sysPageSize - 1);

    if (newSize <= db->mappedSize) return true;
#if _WIN32
    if (db->data) UnmapViewOfFile(db->data);
    if (db->hMap) CloseHandle(db->hMap);
    LARGE_INTEGER li; li.QuadPart = newSize;
    SetFilePointerEx(db->hFile, li, NULL, FILE_BEGIN);
    SetEndOfFile(db->hFile);
    db->hMap = CreateFileMappingA(db->hFile, NULL, PAGE_READWRITE, 0, 0, NULL);
    db->data = MapViewOfFile(db->hMap, FILE_MAP_ALL_ACCESS, 0, 0, 0);
#else
    if (db->data) munmap(db->data, db->mappedSize);
    ftruncate(db->fd, (off_t)newSize);
    db->data = mmap(NULL, newSize, PROT_READ | PROT_WRITE, MAP_SHARED, db->fd, 0);
#endif
    if (!db->data) return false;
    db->mappedSize = newSize;
    DBHeader* h = get_header(db);
    if (h) h->fileSize = newSize;
    return true;
}

static uint64_t allocate_data(DB* db, uint32_t size) {
    uint32_t alignedSize = (size + 7) & ~7; // 8-byte alignment for data
    uint64_t curr = get_header(db)->freeListHead;
    uint64_t prev = 0;
    while (curr != 0) {
        FreeNode* node = (FreeNode*)get_ptr(db, curr);
        if (node->size >= alignedSize) {
            if (prev == 0) get_header(db)->freeListHead = node->next;
            else ((FreeNode*)get_ptr(db, prev))->next = node->next;
            update_header_checksum(db); wal_log_page(db, 0);
            return curr;
        }
        prev = curr;
        curr = node->next;
    }
    if (get_header(db)->dataOffset + alignedSize > db->mappedSize) {
        if (!db_resize(db, db->mappedSize * 2)) return 0;
    }
    uint64_t offset = get_header(db)->dataOffset;
    get_header(db)->dataOffset += alignedSize;
    update_header_checksum(db); wal_log_page(db, 0);
    return offset;
}

static uint64_t allocate_page(DB* db) {
    uint64_t offset = allocate_data(db, STORAGE_BLOCK_SIZE);
    if (offset != 0) memset(get_ptr(db, offset), 0, STORAGE_BLOCK_SIZE);
    return offset;
}

static void deallocate_data(DB* db, uint64_t offset, uint32_t size) {
    if (offset == 0 || size < sizeof(FreeNode)) return;
    FreeNode* node = (FreeNode*)get_ptr(db, offset);
    node->next = get_header(db)->freeListHead;
    node->size = size;
    get_header(db)->freeListHead = offset;
    update_header_checksum(db); wal_log_page(db, 0);
}

static int compare_keys(const char* a, const char* b) {
    return strncmp(a, b, MAX_KEY_LEN);
}

static uint64_t btree_search_offset(DB* db, uint64_t pageOffset, const char* key) {
    if (pageOffset == 0) return 0;
    BTreeNode* node = get_node(db, pageOffset);
    if (!validate_node_checksum(node)) {
        return 0;
    }
    uint32_t i = 0;
    while (i < node->numKeys && compare_keys(key, node->keys[i]) > 0) i++;
    if (i < node->numKeys && compare_keys(key, node->keys[i]) == 0) return node->values[i];
    if (node->isLeaf) return 0;
    return btree_search_offset(db, node->children[i], key);
}

static void btree_split_child(DB* db, uint64_t parentOffset, uint32_t i, uint64_t childOffset) {
    uint64_t newChildOffset = allocate_page(db);
    if (newChildOffset == 0) return;
    BTreeNode* z = get_node(db, newChildOffset);
    BTreeNode* y = get_node(db, childOffset);
    BTreeNode* p = get_node(db, parentOffset);
    z->isLeaf = y->isLeaf;
    z->numKeys = B_DEGREE - 1;
    for (int j = 0; j < B_DEGREE - 1; j++) {
        memcpy(z->keys[j], y->keys[j + B_DEGREE], MAX_KEY_LEN);
        z->values[j] = y->values[j + B_DEGREE];
    }
    if (!y->isLeaf) {
        for (int j = 0; j < B_DEGREE; j++) z->children[j] = y->children[j + B_DEGREE];
    }
    y->numKeys = B_DEGREE - 1;
    for (int j = p->numKeys; j >= (int)i + 1; j--) p->children[j + 1] = p->children[j];
    p->children[i + 1] = newChildOffset;
    for (int j = p->numKeys - 1; j >= (int)i; j--) {
        memcpy(p->keys[j + 1], p->keys[j], MAX_KEY_LEN);
        p->values[j + 1] = p->values[j];
    }
    memcpy(p->keys[i], y->keys[B_DEGREE - 1], MAX_KEY_LEN);
    p->values[i] = y->values[B_DEGREE - 1];
    p->numKeys++;

    update_node_checksum(y); wal_log_page(db, childOffset);
    update_node_checksum(z); wal_log_page(db, newChildOffset);
    update_node_checksum(p); wal_log_page(db, parentOffset);
}

static void btree_borrow_from_prev(DB* db, BTreeNode* parent, uint32_t idx, uint64_t parentOffset) {
    uint64_t childOffset = parent->children[idx];
    uint64_t siblingOffset = parent->children[idx - 1];
    BTreeNode* child = get_node(db, childOffset);
    BTreeNode* sibling = get_node(db, siblingOffset);

    for (int i = (int)child->numKeys - 1; i >= 0; i--) {
        memcpy(child->keys[i + 1], child->keys[i], MAX_KEY_LEN);
        child->values[i + 1] = child->values[i];
    }
    if (!child->isLeaf) {
        for (int i = (int)child->numKeys; i >= 0; i--) child->children[i + 1] = child->children[i];
    }

    memcpy(child->keys[0], parent->keys[idx - 1], MAX_KEY_LEN);
    child->values[0] = parent->values[idx - 1];
    if (!child->isLeaf) child->children[0] = sibling->children[sibling->numKeys];

    memcpy(parent->keys[idx - 1], sibling->keys[sibling->numKeys - 1], MAX_KEY_LEN);
    parent->values[idx - 1] = sibling->values[sibling->numKeys - 1];

    child->numKeys++;
    sibling->numKeys--;

    update_node_checksum(child); wal_log_page(db, childOffset);
    update_node_checksum(sibling); wal_log_page(db, siblingOffset);
    update_node_checksum(parent); wal_log_page(db, parentOffset);
}

static void btree_borrow_from_next(DB* db, BTreeNode* parent, uint32_t idx, uint64_t parentOffset) {
    uint64_t childOffset = parent->children[idx];
    uint64_t siblingOffset = parent->children[idx + 1];
    BTreeNode* child = get_node(db, childOffset);
    BTreeNode* sibling = get_node(db, siblingOffset);

    memcpy(child->keys[child->numKeys], parent->keys[idx], MAX_KEY_LEN);
    child->values[child->numKeys] = parent->values[idx];
    if (!child->isLeaf) child->children[child->numKeys + 1] = sibling->children[0];

    memcpy(parent->keys[idx], sibling->keys[0], MAX_KEY_LEN);
    parent->values[idx] = sibling->values[0];

    for (int i = 1; i < (int)sibling->numKeys; i++) {
        memcpy(sibling->keys[i - 1], sibling->keys[i], MAX_KEY_LEN);
        sibling->values[i - 1] = sibling->values[i];
    }
    if (!sibling->isLeaf) {
        for (int i = 1; i <= (int)sibling->numKeys; i++) sibling->children[i - 1] = sibling->children[i];
    }

    child->numKeys++;
    sibling->numKeys--;

    update_node_checksum(child); wal_log_page(db, childOffset);
    update_node_checksum(sibling); wal_log_page(db, siblingOffset);
    update_node_checksum(parent); wal_log_page(db, parentOffset);
}

static void btree_merge(DB* db, uint64_t parentOffset, uint32_t idx) {
    BTreeNode* parent = get_node(db, parentOffset);
    uint64_t childOffset = parent->children[idx];
    uint64_t siblingOffset = parent->children[idx + 1];
    BTreeNode* child = get_node(db, childOffset);
    BTreeNode* sibling = get_node(db, siblingOffset);

    memcpy(child->keys[B_DEGREE - 1], parent->keys[idx], MAX_KEY_LEN);
    child->values[B_DEGREE - 1] = parent->values[idx];

    for (int i = 0; i < (int)sibling->numKeys; i++) {
        memcpy(child->keys[i + B_DEGREE], sibling->keys[i], MAX_KEY_LEN);
        child->values[i + B_DEGREE] = sibling->values[i];
    }
    if (!child->isLeaf) {
        for (int i = 0; i <= (int)sibling->numKeys; i++) child->children[i + B_DEGREE] = sibling->children[i];
    }

    for (int i = idx + 1; i < (int)parent->numKeys; i++) {
        memcpy(parent->keys[i - 1], parent->keys[i], MAX_KEY_LEN);
        parent->values[i - 1] = parent->values[i];
    }
    for (int i = idx + 2; i <= (int)parent->numKeys; i++) parent->children[i - 1] = parent->children[i];

    child->numKeys += sibling->numKeys + 1;
    parent->numKeys--;

    update_node_checksum(child); wal_log_page(db, childOffset);
    update_node_checksum(parent); wal_log_page(db, parentOffset);
    deallocate_data(db, siblingOffset, STORAGE_BLOCK_SIZE);
}

static void btree_delete_internal(DB* db, uint64_t pageOffset, const char* key) {
    BTreeNode* node = get_node(db, pageOffset);
    uint32_t idx = 0;
    while (idx < node->numKeys && compare_keys(key, node->keys[idx]) > 0) idx++;

    if (idx < node->numKeys && compare_keys(key, node->keys[idx]) == 0) {
        if (node->isLeaf) {
            for (int i = idx + 1; i < (int)node->numKeys; i++) {
                memcpy(node->keys[i - 1], node->keys[i], MAX_KEY_LEN);
                node->values[i - 1] = node->values[i];
            }
            node->numKeys--;
            update_node_checksum(node); wal_log_page(db, pageOffset);
        } else {
            uint64_t predOffset = node->children[idx];
            BTreeNode* predNode = get_node(db, predOffset);
            if (predNode->numKeys >= B_DEGREE) {
                while (!predNode->isLeaf) {
                    predOffset = predNode->children[predNode->numKeys];
                    predNode = get_node(db, predOffset);
                }
                char predKey[MAX_KEY_LEN];
                memcpy(predKey, predNode->keys[predNode->numKeys - 1], MAX_KEY_LEN);
                uint64_t predVal = predNode->values[predNode->numKeys - 1];
                memcpy(node->keys[idx], predKey, MAX_KEY_LEN);
                node->values[idx] = predVal;
                update_node_checksum(node); wal_log_page(db, pageOffset);
                btree_delete_internal(db, node->children[idx], predKey);
            } else {
                uint64_t succOffset = node->children[idx + 1];
                BTreeNode* succNode = get_node(db, succOffset);
                if (succNode->numKeys >= B_DEGREE) {
                    while (!succNode->isLeaf) {
                        succOffset = succNode->children[0];
                        succNode = get_node(db, succOffset);
                    }
                    char succKey[MAX_KEY_LEN];
                    memcpy(succKey, succNode->keys[0], MAX_KEY_LEN);
                    uint64_t succVal = succNode->values[0];
                    memcpy(node->keys[idx], succKey, MAX_KEY_LEN);
                    node->values[idx] = succVal;
                    update_node_checksum(node); wal_log_page(db, pageOffset);
                    btree_delete_internal(db, node->children[idx + 1], succKey);
                } else {
                    btree_merge(db, pageOffset, idx);
                    btree_delete_internal(db, node->children[idx], key);
                }
            }
        }
    } else {
        if (node->isLeaf) return;
        bool lastChild = (idx == node->numKeys);
        uint64_t childOffset = node->children[idx];
        BTreeNode* child = get_node(db, childOffset);
        if (child->numKeys < B_DEGREE) {
            if (idx > 0 && get_node(db, node->children[idx - 1])->numKeys >= B_DEGREE)
                btree_borrow_from_prev(db, node, idx, pageOffset);
            else if (idx < node->numKeys && get_node(db, node->children[idx + 1])->numKeys >= B_DEGREE)
                btree_borrow_from_next(db, node, idx, pageOffset);
            else {
                if (idx < node->numKeys) btree_merge(db, pageOffset, idx);
                else { btree_merge(db, pageOffset, idx - 1); idx--; }
            }
        }
        btree_delete_internal(db, node->children[idx], key);
    }
}

static uint64_t btree_delete(DB* db, uint64_t rootOffset, const char* key) {
    if (rootOffset == 0) return 0;
    btree_delete_internal(db, rootOffset, key);
    BTreeNode* root = get_node(db, rootOffset);
    if (root->numKeys == 0 && !root->isLeaf) {
        uint64_t newRoot = root->children[0];
        deallocate_data(db, rootOffset, STORAGE_BLOCK_SIZE);
        return newRoot;
    }
    return rootOffset;
}

static void btree_insert_nonfull(DB* db, uint64_t pageOffset, const char* key, uint64_t value) {
    BTreeNode* node = get_node(db, pageOffset);
    uint32_t idx = 0;
    while (idx < node->numKeys && compare_keys(key, node->keys[idx]) > 0) idx++;
    if (idx < node->numKeys && compare_keys(key, node->keys[idx]) == 0) {
        node->values[idx] = value;
        update_node_checksum(node); wal_log_page(db, pageOffset);
        return;
    }

    if (node->isLeaf) {
        int i = (int)node->numKeys - 1;
        while (i >= (int)idx) {
            memcpy(node->keys[i + 1], node->keys[i], MAX_KEY_LEN);
            node->values[i + 1] = node->values[i]; i--;
        }
        memset(node->keys[idx], 0, MAX_KEY_LEN);
        strncpy(node->keys[idx], key, MAX_KEY_LEN - 1);
        node->values[idx] = value;
        node->numKeys++;
        update_node_checksum(node); wal_log_page(db, pageOffset);
    } else {
        uint64_t childOffset = node->children[idx];
        if (get_node(db, childOffset)->numKeys == 2 * B_DEGREE - 1) {
            btree_split_child(db, pageOffset, idx, childOffset);
            node = get_node(db, pageOffset);
            if (compare_keys(key, node->keys[idx]) > 0) idx++;
            childOffset = node->children[idx];
        }
        btree_insert_nonfull(db, childOffset, key, value);
    }
}

static uint64_t btree_put(DB* db, uint64_t rootOffset, const char* key, uint64_t value) {
    if (rootOffset == 0) {
        rootOffset = allocate_page(db);
        BTreeNode* root = get_node(db, rootOffset);
        memset(root, 0, STORAGE_BLOCK_SIZE);
        root->isLeaf = 1;
        update_node_checksum(root); wal_log_page(db, rootOffset);
    }
    if (get_node(db, rootOffset)->numKeys == 2 * B_DEGREE - 1) {
        uint64_t newRootOffset = allocate_page(db);
        BTreeNode* s = get_node(db, newRootOffset);
        memset(s, 0, STORAGE_BLOCK_SIZE);
        s->isLeaf = 0;
        s->children[0] = rootOffset;
        btree_split_child(db, newRootOffset, 0, rootOffset);
        btree_insert_nonfull(db, newRootOffset, key, value);
        return newRootOffset;
    } else {
        btree_insert_nonfull(db, rootOffset, key, value);
        return rootOffset;
    }
}

static bool lock_file(DB* db, bool exclusive) {
#if _WIN32
    OVERLAPPED ov = {0};
    DWORD flags = exclusive ? LOCKFILE_EXCLUSIVE_LOCK : 0;
    if (!LockFileEx(db->hFile, flags, 0, 0xFFFFFFFF, 0xFFFFFFFF, &ov)) return false;
#else
    int flags = exclusive ? LOCK_EX : LOCK_SH;
    if (flock(db->fd, flags) != 0) return false;
#endif

    // Synchronize memory mapping if file grew on disk (multi-process safety)
    uint64_t currentFileSize = 0;
#if _WIN32
    LARGE_INTEGER li;
    if (GetFileSizeEx(db->hFile, &li)) {
        currentFileSize = li.QuadPart;
    }
#else
    struct stat st;
    if (fstat(db->fd, &st) == 0) {
        currentFileSize = st.st_size;
    }
#endif
    if (currentFileSize > db->mappedSize) {
        db_resize(db, currentFileSize);
    }
    return true;
}

static void unlock_file(DB* db) {
#if _WIN32
    OVERLAPPED ov = {0};
    UnlockFileEx(db->hFile, 0, 0xFFFFFFFF, 0xFFFFFFFF, &ov);
#else
    flock(db->fd, LOCK_UN);
#endif
}

FFI_PLUGIN_EXPORT DB* db_open(const char* path, const unsigned char* encryption_key) {
    if (!crc32_table_computed) make_crc32_table();
    DB* db = new DB();
    if (!db) return NULL;
    db->data = NULL;
    db->mappedSize = 0;
    db->use_encryption = false;

    // Initialize WAL path
    snprintf(db->wal_path, sizeof(db->wal_path), "%s.wal", path);

    if (encryption_key) {
        memcpy(db->encryption_key, encryption_key, 32);
        db->use_encryption = true;
    }
#if _WIN32
    db->hFile = CreateFileA(path, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (db->hFile == INVALID_HANDLE_VALUE) {
        delete db; return NULL;
    }
    uint32_t low, high; low = GetFileSize(db->hFile, (LPDWORD)&high);
    db->mappedSize = ((uint64_t)high << 32) | low;

    db->hWal = CreateFileA(db->wal_path, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
#else
    db->fd = open(path, O_RDWR | O_CREAT, 0644);
    if (db->fd < 0) { delete db; return NULL; }
    struct stat st; fstat(db->fd, &st);
    db->mappedSize = st.st_size;

    db->wal_fd = open(db->wal_path, O_RDWR | O_CREAT, 0644);
#endif

    if (db->mappedSize < STORAGE_BLOCK_SIZE) {
        db->mappedSize = STORAGE_BLOCK_SIZE * 1024;
#if _WIN32
        LARGE_INTEGER li; li.QuadPart = db->mappedSize;
        SetFilePointerEx(db->hFile, li, NULL, FILE_BEGIN); SetEndOfFile(db->hFile);
#else
        ftruncate(db->fd, (off_t)db->mappedSize);
#endif
    }
#if _WIN32
    db->hMap = CreateFileMappingA(db->hFile, NULL, PAGE_READWRITE, 0, 0, NULL);
    db->data = MapViewOfFile(db->hMap, FILE_MAP_ALL_ACCESS, 0, 0, 0);
#else
    db->data = mmap(NULL, db->mappedSize, PROT_READ | PROT_WRITE, MAP_SHARED, db->fd, 0);
#endif
    if (!db->data) {
#if _WIN32
        if (db->hFile != INVALID_HANDLE_VALUE) CloseHandle(db->hFile);
        if (db->hWal != INVALID_HANDLE_VALUE) CloseHandle(db->hWal);
#else
        if (db->fd >= 0) close(db->fd);
        if (db->wal_fd >= 0) close(db->wal_fd);
#endif
        delete db; return NULL;
    }

    // Recover from WAL if needed - MUST LOCK
    if (lock_file(db, true)) {
        wal_replay(db);

        DBHeader* h = get_header(db);
        if (strncmp(h->magic, "FLRE", 4) != 0) {
            memset(h, 0, sizeof(DBHeader));
            memcpy(h->magic, "FLRE", 4);
            h->version = 1;
            h->fileSize = db->mappedSize;
            h->dataOffset = STORAGE_BLOCK_SIZE; // Start after header page
            update_header_checksum(db);
        }
        unlock_file(db);
    }

    return db;
}

FFI_PLUGIN_EXPORT void db_close(DB* db) {
    if (!db) return;
#if _WIN32
    if (db->data) UnmapViewOfFile(db->data);
    if (db->hMap) CloseHandle(db->hMap);
    if (db->hFile != INVALID_HANDLE_VALUE) CloseHandle(db->hFile);
    if (db->hWal != INVALID_HANDLE_VALUE) CloseHandle(db->hWal);
#else
    if (db->data) munmap(db->data, db->mappedSize);
    if (db->fd >= 0) close(db->fd);
    if (db->wal_fd >= 0) close(db->wal_fd);
#endif
    delete db;
}

FFI_PLUGIN_EXPORT int64_t db_put(DB* db, const char* key, const char* json) {
    if (!db || !key || !json) return -1;
    std::lock_guard<std::mutex> lock(db->mtx);
    if (!lock_file(db, true)) return -1;

    size_t raw_len = strlen(json);
    if (raw_len > 0x7FFFFFFF) { // Safety limit for 31-bit sizes
        unlock_file(db);
        return -1;
    }
    uint32_t len = (uint32_t)raw_len;

    char* data_to_write = NULL;
    uint32_t totalSize;
    if (db->use_encryption) {
        totalSize = sizeof(uint32_t) + 16 + len + 1;
        data_to_write = (char*)malloc(totalSize);
        if (!data_to_write) { unlock_file(db); return -1; }
        memcpy(data_to_write, &len, sizeof(uint32_t));
        generate_random((unsigned char*)data_to_write + sizeof(uint32_t), 16);
        memcpy(data_to_write + sizeof(uint32_t) + 16, json, len + 1);
        AES256::crypt_ctr((unsigned char*)data_to_write + sizeof(uint32_t) + 16, len, db->encryption_key, (unsigned char*)data_to_write + sizeof(uint32_t));
    } else {
        totalSize = sizeof(uint32_t) + len + 1;
        data_to_write = (char*)malloc(totalSize);
        if (!data_to_write) { unlock_file(db); return -1; }
        memcpy(data_to_write, &len, sizeof(uint32_t));
        memcpy(data_to_write + sizeof(uint32_t), json, len + 1);
    }

    uint64_t existingOffset = btree_search_offset(db, get_header(db)->rootPage, key);
    if (existingOffset != 0) {
        char* ptr = (char*)get_ptr(db, existingOffset);
        uint32_t oldDataLen; memcpy(&oldDataLen, ptr, sizeof(uint32_t));
        uint32_t oldTotalSize = db->use_encryption ? (sizeof(uint32_t) + 16 + oldDataLen + 1) : (sizeof(uint32_t) + oldDataLen + 1);
        if (totalSize <= oldTotalSize) {
            memcpy(ptr, data_to_write, totalSize);
            wal_log_page(db, existingOffset & ~(STORAGE_BLOCK_SIZE - 1));
            free(data_to_write);
            unlock_file(db);
            return (int64_t)existingOffset;
        } else {
            deallocate_data(db, existingOffset, oldTotalSize);
        }
    }
    uint64_t dataOffset = allocate_data(db, totalSize);
    if (dataOffset == 0) {
        free(data_to_write);
        unlock_file(db);
        return -1;
    }
    memcpy(get_ptr(db, dataOffset), data_to_write, totalSize);
    wal_log_page(db, dataOffset & ~(STORAGE_BLOCK_SIZE - 1));
    free(data_to_write);

    uint64_t newRoot = btree_put(db, get_header(db)->rootPage, key, dataOffset);
    if (newRoot != get_header(db)->rootPage) {
        get_header(db)->rootPage = newRoot;
        update_header_checksum(db); wal_log_page(db, 0);
    }
#if _WIN32
    FlushViewOfFile(db->data, 0);
#else
    msync(db->data, (size_t)db->mappedSize, MS_SYNC);
#endif
    unlock_file(db);
    return (int64_t)dataOffset;
}

// Removed global decryption_buffer

FFI_PLUGIN_EXPORT const char* db_get_by_key(DB* db, const char* key) {
    if (!db || !key) return NULL;
    std::lock_guard<std::mutex> lock(db->mtx);
    if (!lock_file(db, false)) return NULL;
    uint64_t offset = btree_search_offset(db, get_header(db)->rootPage, key);
    if (offset == 0) { unlock_file(db); return NULL; }

    char* ptr = (char*)get_ptr(db, offset);
    uint32_t len; memcpy(&len, ptr, sizeof(uint32_t));
    char* result = (char*)malloc(len + 1);
    if (!result) { unlock_file(db); return NULL; }

    if (db->use_encryption) {
        const unsigned char* iv = (const unsigned char*)ptr + sizeof(uint32_t);
        const char* raw_json = ptr + sizeof(uint32_t) + 16;
        memcpy(result, raw_json, len);
        result[len] = '\0';
        AES256::crypt_ctr((unsigned char*)result, len, db->encryption_key, iv);
    } else {
        const char* raw_json = ptr + sizeof(uint32_t);
        memcpy(result, raw_json, len);
        result[len] = '\0';
    }

    unlock_file(db);
    return result;
}

FFI_PLUGIN_EXPORT const char* db_get(DB* db, int64_t id) {
    if (!db || id < (int64_t)STORAGE_BLOCK_SIZE || (size_t)id >= db->mappedSize) return NULL;
    std::lock_guard<std::mutex> lock(db->mtx);
    if (!lock_file(db, false)) return NULL;
    char* ptr = (char*)get_ptr(db, (uint64_t)id);
    uint32_t len; memcpy(&len, ptr, sizeof(uint32_t));
    char* result = (char*)malloc(len + 1);
    if (!result) { unlock_file(db); return NULL; }

    if (db->use_encryption) {
        const unsigned char* iv = (const unsigned char*)ptr + sizeof(uint32_t);
        const char* raw_json = ptr + sizeof(uint32_t) + 16;
        memcpy(result, raw_json, len);
        result[len] = '\0';
        AES256::crypt_ctr((unsigned char*)result, len, db->encryption_key, iv);
    } else {
        const char* raw_json = ptr + sizeof(uint32_t);
        memcpy(result, raw_json, len);
        result[len] = '\0';
    }
    unlock_file(db);
    return result;
}

FFI_PLUGIN_EXPORT bool db_delete(DB* db, const char* key) {
    if (!db || !key) return false;
    std::lock_guard<std::mutex> lock(db->mtx);
    if (!lock_file(db, true)) return false;

    uint64_t existingOffset = btree_search_offset(db, get_header(db)->rootPage, key);
    if (existingOffset == 0) {
        unlock_file(db);
        return false;
    }

    // Free the actual data
    uint32_t len; memcpy(&len, get_ptr(db, existingOffset), sizeof(uint32_t));
    deallocate_data(db, existingOffset, sizeof(uint32_t) + len + 1);

    // Remove from B-Tree
    uint64_t newRoot = btree_delete(db, get_header(db)->rootPage, key);
    if (newRoot != get_header(db)->rootPage) {
        get_header(db)->rootPage = newRoot;
        update_header_checksum(db);
        wal_log_page(db, 0);
    }

#if _WIN32
    FlushViewOfFile(db->data, 0);
#else
    msync(db->data, (size_t)db->mappedSize, MS_SYNC);
#endif
    unlock_file(db);
    return true;
}

FFI_PLUGIN_EXPORT void db_sync(DB* db) {
    if (!db || !db->data) return;
    std::lock_guard<std::mutex> lock(db->mtx);
    if (!lock_file(db, true)) return;

#if _WIN32
    FlushFileBuffers(db->hWal);
    FlushViewOfFile(db->data, 0);
    FlushFileBuffers(db->hFile);
    // Clear WAL
    SetFilePointer(db->hWal, 0, NULL, FILE_BEGIN);
    SetEndOfFile(db->hWal);
#else
    fsync(db->wal_fd);
    msync(db->data, (size_t)db->mappedSize, MS_SYNC);
    // Clear WAL
    ftruncate(db->wal_fd, 0);
    lseek(db->wal_fd, 0, SEEK_SET);
#endif
    unlock_file(db);
}

FFI_PLUGIN_EXPORT void db_set_key(DB* db, const unsigned char* key) {
    if (!db || !key) return;
    std::lock_guard<std::mutex> lock(db->mtx);
    memcpy(db->encryption_key, key, 32);
    db->use_encryption = true;
}

FFI_PLUGIN_EXPORT DBIterator* db_iterator_open(DB* db, uint64_t rootOffset, const char* start, const char* end) {
    if (!db) return NULL;
    std::lock_guard<std::mutex> lock(db->mtx);
    if (!lock_file(db, false)) return NULL;
    DBIterator* it = (DBIterator*)malloc(sizeof(DBIterator));
    if (!it) { unlock_file(db); return NULL; }
    memset(it, 0, sizeof(DBIterator));
    it->db = db; it->root = rootOffset == 0 ? get_header(db)->rootPage : rootOffset;
    if (end) {
        strncpy(it->endKey, end, MAX_KEY_LEN - 1);
        it->endKey[MAX_KEY_LEN - 1] = '\0';
    }
    uint64_t pageOffset = it->root;
    while (pageOffset != 0) {
        BTreeNode* node = get_node(db, pageOffset);
        if (!validate_node_checksum(node)) { it->stackSize = 0; break; }
        uint32_t i = 0;
        if (start) while (i < node->numKeys && compare_keys(start, node->keys[i]) > 0) i++;
        it->stack[it->stackSize].pageOffset = pageOffset;
        it->stack[it->stackSize].keyIndex = i;
        it->stackSize++;
        if (node->isLeaf) break;
        pageOffset = node->children[i];
    }
    unlock_file(db);
    return it;
}

FFI_PLUGIN_EXPORT bool db_iterator_next(DBIterator* it, const char** key, const char** json) {
    if (!it || !it->db) return false;
    std::lock_guard<std::mutex> lock(it->db->mtx);
    if (!lock_file(it->db, false)) return false;
    while (it->stackSize > 0) {
        int top = it->stackSize - 1;
        uint64_t pageOffset = it->stack[top].pageOffset;
        uint32_t keyIndex = it->stack[top].keyIndex;
        BTreeNode* node = get_node(it->db, pageOffset);
        if (!validate_node_checksum(node)) { it->stackSize = 0; unlock_file(it->db); return false; }
        if (keyIndex < node->numKeys) {
            it->stack[top].keyIndex++;
            if (it->endKey[0] != 0 && compare_keys(node->keys[keyIndex], it->endKey) > 0) {
                it->stackSize = 0; unlock_file(it->db); return false;
            }
            *key = node->keys[keyIndex];
            uint64_t valOffset = node->values[keyIndex];
            if (!node->isLeaf) {
                uint64_t childOffset = node->children[keyIndex + 1];
                while (childOffset != 0) {
                    BTreeNode* child = get_node(it->db, childOffset);
                    if (!validate_node_checksum(child)) { it->stackSize = 0; unlock_file(it->db); return false; }
                    it->stack[it->stackSize].pageOffset = childOffset;
                    it->stack[it->stackSize].keyIndex = 0;
                    it->stackSize++;
                    if (child->isLeaf) break;
                    childOffset = child->children[0];
                }
            }

            if (valOffset != 0) {
                char* ptr = (char*)get_ptr(it->db, valOffset);
                uint32_t len; memcpy(&len, ptr, sizeof(uint32_t));
                char* result = (char*)malloc(len + 1);
                if (!result) { unlock_file(it->db); return false; }

                if (it->db->use_encryption) {
                    const unsigned char* iv = (const unsigned char*)ptr + sizeof(uint32_t);
                    const char* raw_json = ptr + sizeof(uint32_t) + 16;
                    memcpy(result, raw_json, len);
                    result[len] = '\0';
                    AES256::crypt_ctr((unsigned char*)result, len, it->db->encryption_key, iv);
                } else {
                    const char* raw_json = ptr + sizeof(uint32_t);
                    memcpy(result, raw_json, len);
                    result[len] = '\0';
                }
                *json = result;
            } else {
                *json = (char*)malloc(1);
                ((char*)*json)[0] = '\0';
            }
            unlock_file(it->db);
            return true;
        } else it->stackSize--;
    }
    unlock_file(it->db);
    return false;
}

FFI_PLUGIN_EXPORT void db_iterator_close(DBIterator* it) {
    if (it) free(it);
}

FFI_PLUGIN_EXPORT int32_t db_create_index(DB* db, const char* name) {
    if (!db) return -1;
    std::lock_guard<std::mutex> lock(db->mtx);
    DBHeader* h = get_header(db);
    for (int i = 0; i < MAX_SECONDARY_INDEXES; i++) {
        if (h->indexNames[i][0] == 0) {
            strncpy(h->indexNames[i], name, 31);
            h->indexNames[i][31] = '\0';
            update_header_checksum(db); wal_log_page(db, 0);
            return i;
        }
        if (strncmp(h->indexNames[i], name, 31) == 0) return i;
    }
    return -1;
}

FFI_PLUGIN_EXPORT const char* db_get_index_name(DB* db, int32_t indexIdx) {
    if (!db || indexIdx < 0 || indexIdx >= MAX_SECONDARY_INDEXES) return NULL;
    std::lock_guard<std::mutex> lock(db->mtx);
    DBHeader* h = get_header(db);
    if (h->indexNames[indexIdx][0] == '\0') return NULL;
    return strdup(h->indexNames[indexIdx]);
}

FFI_PLUGIN_EXPORT uint64_t db_get_root(DB* db, int32_t indexIdx) {
    if (!db || indexIdx < 0 || indexIdx >= MAX_SECONDARY_INDEXES) return 0;
    return get_header(db)->secondaryRoots[indexIdx];
}

FFI_PLUGIN_EXPORT void db_put_secondary(DB* db, int32_t indexIdx, const char* secKey, const char* primKey) {
    if (!db || indexIdx < 0 || indexIdx >= MAX_SECONDARY_INDEXES || !secKey || !primKey) return;
    std::lock_guard<std::mutex> lock(db->mtx);
    if (!lock_file(db, true)) return;

    // Use a composite key: secKey + \x1F + primKey
    char composite[MAX_KEY_LEN];
    snprintf(composite, MAX_KEY_LEN, "%s\x1F%s", secKey, primKey);

    uint64_t newRoot = btree_put(db, get_header(db)->secondaryRoots[indexIdx], composite, 0);
    if (newRoot != get_header(db)->secondaryRoots[indexIdx]) {
        get_header(db)->secondaryRoots[indexIdx] = newRoot;
        update_header_checksum(db); wal_log_page(db, 0);
    }
#if _WIN32
    FlushViewOfFile(db->data, 0);
#else
    msync(db->data, (size_t)db->mappedSize, MS_SYNC);
#endif
    unlock_file(db);
}

FFI_PLUGIN_EXPORT void db_remove_secondary(DB* db, int32_t indexIdx, const char* secKey, const char* primKey) {
    if (!db || indexIdx < 0 || indexIdx >= MAX_SECONDARY_INDEXES || !secKey || !primKey) return;
    std::lock_guard<std::mutex> lock(db->mtx);
    if (!lock_file(db, true)) return;

    char composite[MAX_KEY_LEN];
    snprintf(composite, MAX_KEY_LEN, "%s\x1F%s", secKey, primKey);

    uint64_t newRoot = btree_delete(db, get_header(db)->secondaryRoots[indexIdx], composite);
    if (newRoot != get_header(db)->secondaryRoots[indexIdx]) {
        get_header(db)->secondaryRoots[indexIdx] = newRoot;
        update_header_checksum(db); wal_log_page(db, 0);
    }
#if _WIN32
    FlushViewOfFile(db->data, 0);
#else
    msync(db->data, (size_t)db->mappedSize, MS_SYNC);
#endif
    unlock_file(db);
}

FFI_PLUGIN_EXPORT void db_free_string(const char* s) {
    if (s) free((void*)s);
}

}
