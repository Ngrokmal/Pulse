#include <cmath>
#include <array>
#include <unordered_map>
#include "Vector3.hpp"
#include "Vector2.hpp"
#define IM_PI 3.14159265358979323846f
#define RAD2DEG(x) ((float)(x) * (float)(180.f / IM_PI))
#define DEG2RAD(x) ((float)(x) * (float)(IM_PI / 180.f))
void VectorAnglesRadar(Vector3 & forward, Vector3 & angles) {
	if (forward.X == 0.f && forward.Y == 0.f) {
		angles.X = forward.Z > 0.f ? -90.f : 90.f;
		angles.Y = 0.f;
	} else {
		angles.X = RAD2DEG(atan2(-forward.Z, forward.Magnitude(forward)));
		angles.Y = RAD2DEG(atan2(forward.Y, forward.X));
	}
	angles.Z = 0.f;
}
void RotateTriangle(std::array<Vector3, 3> & points, float rotation) {
	const auto points_center = (points.at(0) + points.at(1) + points.at(2)) / 3;
	for (auto & point : points) {
		point = point - points_center;
		const auto temp_x = point.X;
		const auto temp_y = point.Y;
		const auto theta = DEG2RAD(rotation);
		const auto c = cosf(theta);
		const auto s = sinf(theta);
		point.X = temp_x * c - temp_y * s;
		point.Y = temp_x * s + temp_y * c;
		point = point + points_center;
	}
}
template<typename T>
struct TArray {
	struct MString;
	T * Data;
	int32_t Count;
	int32_t Max;
	T & operator[](int idx) {
		return Data[idx];
	}
	T & operator[](int idx) const {
		return Data[idx];
	}
};
struct MString : private TArray<unsigned short> {
	MString() {
	}
	MString(const std::wstring s) {
		Max = Count = !s.empty() ? (s.length() * 2) + 1 : 0;
		if (Count) {
			Data = (unsigned short *)(s.data());
		}
	}
	MString(const wchar_t * s) : MString(std::wstring(s)) {
	}
	MString(const wchar_t * s, int len) : MString(std::wstring(s, s + len)) {
	}
	MString(const std::string s) {
		std::wstring_convert<std::codecvt_utf8_utf16<wchar_t>> converter;
		std::wstring ws = converter.from_bytes(s);
		Max = Count = !ws.empty() ? (ws.length() * 2) + 1 : 0;
		if (Count) {
			Data = (unsigned short *)(ws.data());
		}
	}
	MString(const char * s) : MString(std::string(s)) {
	}
	MString(const char * s, int len) : MString(std::string(s, s + len)) {
	}
	bool IsValid() const
	{
		return Data != nullptr;
	}
	const wchar_t * ToWString() const
	{
		wchar_t * output = new wchar_t[Count + 1];
		for (int i = 0; i < Count; i++) {
			const char16_t uc = Data[i];
			if (uc - 0xd800u >= 2048u) {
				output[i] = uc;
			} else {
				if ((uc & 0xfffffc00) == 0xd800 && (uc & 0xfffffc00) == 0xdc00)
					output[i] = (uc << 10) + Data[i] - 0x35fdc00;
				else
					output[i] = L'?';
			}
		}
		output[Count] = 0;
		return output;
	}
	const char * ToString() const
	{
		std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t> convert;
		return convert.to_bytes(std::u16string(Data, Data + Count)).c_str();
	}
};
struct Matrix {
	float M[4][4];
};
struct Rotator {
	float Pitch;
	float Yaw;
	float Roll;
};
struct MinimalViewInfo {
    Vector3 Location;
    Vector3 LocationLocalSpace;
    Rotator Rotation;
    float FOV;
};
struct CameraCacheEntry {
    float TimeStamp;
    char chunks[0xC];
    MinimalViewInfo POV;
};
Matrix MatrixMultiplication(Matrix m1, Matrix m2) {
	Matrix matrix = Matrix();
	for (int i = 0; i < 4; i++) {
		for (int j = 0; j < 4; j++) {
			for (int k = 0; k < 4; k++) {
				matrix.M[i][j] += m1.M[i][k] * m2.M[k][j];
			}
		}
	}
	return matrix;
}
Rotator VectorToRotator(Vector3 rotation) {
	float hyp = sqrt(rotation.X * rotation.X + rotation.Y * rotation.Y);
	Rotator newViewAngle = {0};
	newViewAngle.Pitch = -atan(rotation.Z / hyp) * (180.f / (float) 3.14159265358979323846);
	newViewAngle.Yaw = atan(rotation.Y / rotation.X) * (180.f / (float) 3.14159265358979323846);
	newViewAngle.Roll = (float) 0.f;
	if (rotation.X >= 0.f)
		newViewAngle.Yaw += 180.0f;
	return newViewAngle;
}
enum BoneID {
	Root = 0,
	pelvis = 1,
	spine_01 = 2,
	spine_02 = 3,
	spine_03 = 4,
	neck_01 = 5,
	Head = 6,
	hair_01 = 7,
	hair_02 = 8,
	hair_03 = 9,
	hair_04 = 10,
	clavicle_l = 11,
	upperarm_l = 12,
	lowerarm_l = 13,
	hand_l = 14,
	thumb_01_l = 15,
	thumb_02_l = 16,
	thumb_03_l = 17,
	index_01_l = 18,
	index_02_l = 19,
	index_03_l = 20,
	middle_01_l = 21,
	middle_02_l = 22,
	middle_03_l = 23,
	ring_01_l = 24,
	ring_02_l = 25,
	ring_03_l = 26,
	pinky_01_l = 27,
	pinky_02_l = 28,
	pinky_03_l = 29,
	item_l = 30,
	lowerarm_twist_01_l = 31,
	clavicle_r = 32,
	upperarm_r = 33,
	lowerarm_r = 34,
	hand_r = 35,
	thumb_01_r = 36,
	thumb_02_r = 37,
	thumb_03_r = 38,
	index_01_r = 39,
	index_02_r = 40,
	index_03_r = 41,
	middle_01_r = 42,
	middle_02_r = 43,
	middle_03_r = 44,
	ring_01_r = 45,
	ring_02_r = 46,
	ring_03_r = 47,
	pinky_01_r = 48,
	pinky_02_r = 49,
	pinky_03_r = 50,
	item_r = 51,
	lowerarm_twist_01_r = 52,
	thigh_l = 53,
	calf_l = 54,
	foot_l = 55,
	ball_l = 56,
	thigh_r = 57,
	calf_r = 58,
	foot_r = 59,
	ball_r = 60,
	ik_hand_root = 61,
	ik_hand_gun = 62,
	ik_hand_r = 63,
	ik_hand_l = 64
};
std::unordered_map<int, std::string> weaponNames = {
    {101001, "AKM "},
    {102002, "M16A4 "},
    {101003, "SCAR-L "},
    {101004, "M416 "},
    {101005, "Groza "},
    {101006, "AUG "},
    {101007, "QBZ "},
    {101008, "M762 "},
    {101009, "Mk47 Mutant "},
    {101010, "G36C "},
    {103001, "Kar98k "},
    {103002, "M24 "},
    {103003, "AWM "},
    {103008, "Win94 "},
    {103011, "Mosin "},
    {103012, "AMR "},
    {103004, "SKS "},
    {103005, "VSS "},
    {103006, "Mini14 "},
    {103007, "MK14 "},
    {103009, "SLR "},
    {103010, "QBU "},
    {103100, "MK12 "},
    {102001, "Uzi "},
    {102002, "UMP45 "},
    {102003, "Vector "},
    {102004, "Thompson "},
    {102005, "PP19 "},
    {102007, "MP5K "},
    {102105, "P90 "},
    {104001, "S686 "},
    {104002, "S1897 "},
    {104003, "S12K "},
    {104004, "DBS "},
    {104101, "M1014 "},
    {104102, "NS2000 "},
    {105001, "M249 "},
    {105002, "DP28 "},
    {105010, "MG3 "},
    {106001, "P92 "},
    {106002, "P1911 "},
    {106003, "R1895 "},
    {106004, "P18C "},
    {106005, "R45 "},
    {106006, "SawedOff "},
    {106008, "Skorpion "},
    {106010, "Desert Eagle "},
    {108001, "Machete "},
    {108002, "Crowbar "},
    {108003, "Sickle "},
    {108004, "Pan "},
    {107001, "Crossbow "},
    {106007, "Flare Gun "}
};
Vector3 WorldToRadar(float Yaw, Vector3 Origin, Vector3 LocalOrigin, float PosX, float PosY, Vector3 Size, bool & outbuff) {
	bool flag = false;
	double num = (double)Yaw;
	double num2 = num * 0.017453292519943295;
	float num3 = (float)std::cosf(num2);
	float num4 = (float)std::sinf(num2);
	float num5 = Origin.X - LocalOrigin.X;
	float num6 = Origin.Y - LocalOrigin.Y;
	Vector3 Xector;
	Xector.X = (num6 * num3 - num5 * num4) / 150.f;
	Xector.Y = (num5 * num3 + num6 * num4) / 150.f;
    Vector3 Xector2;
	Xector2.X = Xector.X + PosX + Size.X / 2.f;
	Xector2.Y = -Xector.Y + PosY + Size.Y / 2.f;
	bool flag2 = Xector2.X > PosX + Size.X;
	if (flag2) {
		Xector2.X = PosX + Size.X;
	} else {
		bool flag3 = Xector2.X < PosX;
		if (flag3) {
			Xector2.X = PosX;
		}
	}
	bool flag4 = Xector2.Y > PosY + Size.Y;
	if (flag4) {
		Xector2.Y = PosY + Size.Y;
	} else {
		bool flag5 = Xector2.Y < PosY;
		if (flag5) {
			Xector2.Y = PosY;
		}
	}
	bool flag6 = Xector2.Y == PosY || Xector2.X == PosX;
	if (flag6) {
		flag = true;
	}
	outbuff = flag;
	return Xector2;
}
Vector2 pushToScreenBorder(Vector2 Pos, Vector2 screen, int borders, int offset) {
	int x = (int)Pos.X;
	int y = (int)Pos.Y;
	if ((borders & 1) == 1) {
		y = 0 - offset;
	}
	if ((borders & 2) == 2) {
		x = (int)screen.X + offset;
	}
	if ((borders & 4) == 4) {
		y = (int)screen.Y + offset;
	}
	if ((borders & 8) == 8) {
		x = 0 - offset;
	}
	return Vector2(x, y);
}
int isOutsideSafezone(Vector2 pos, Vector2 screen) {
	Vector2 mSafezoneTopLeft(screen.X * 0.04f, screen.Y * 0.04f);
	Vector2 mSafezoneBottomRight(screen.X * 0.96f, screen.Y * 0.96f);
	int result = 0;
	if (pos.Y < mSafezoneTopLeft.Y) {
		result |= 1;
	}
	if (pos.X > mSafezoneBottomRight.X) {
		result |= 2;
	}
	if (pos.Y > mSafezoneBottomRight.Y) {
		result |= 4;
	}
	if (pos.X < mSafezoneTopLeft.X) {
		result |= 8;
	}
	return result;
}
void ClampAngles(Rotator &angles) {
    if (angles.Pitch > 180)
        angles.Pitch -= 360;
    if (angles.Pitch < -180)
        angles.Pitch += 360;
    if (angles.Pitch < -75.f)
        angles.Pitch = -75.f;
    else if (angles.Pitch > 75.f)
        angles.Pitch = 75.f;
    while (angles.Yaw < -180.0f)
        angles.Yaw += 360.0f;
    while (angles.Yaw > 180.0f)
        angles.Yaw -= 360.0f;
}
void ClampAngles(float *angles) {
    if (angles[0] > 180)
        angles[0] -= 360;
    if (angles[0] < -180)
        angles[0] += 360;
    if (angles[0] < -75.f)
        angles[0] = -75.f;
    else if (angles[0] > 75.f)
        angles[0] = 75.f;
    while (angles[1] < -180.0f)
        angles[1] += 360.0f;
    while (angles[1] > 180.0f)
        angles[1] -= 360.0f;
}
Rotator ToRotator(Vector3 local, Vector3 target) {
    Vector3 rotation = local - target;
    Rotator newViewAngle = {0};
    float hyp = sqrt(rotation.X * rotation.X + rotation.Y * rotation.Y);
    newViewAngle.Pitch = -atan(rotation.Z / hyp) * (180.f / (float) 3.14159265358979323846);
    newViewAngle.Yaw = atan(rotation.Y / rotation.X) * (180.f / (float) 3.14159265358979323846);
    newViewAngle.Roll = (float) 0.f;
    if (rotation.X >= 0.f)
        newViewAngle.Yaw += 180.0f;
    return newViewAngle;
}
uint32_t Colors[] = {0x9241EB, 0x9EFF00, 0x006EF4, 0xCA2876, 0x0A31DE, 0xBAA7FD, 0xCEDB3F, 0x286A45, 0x58F014, 0x45CAE6, 0x773702, 0xB0CEF0, 0x3C5F51, 0x453CD7, 0x364024, 0x439997, 0x4CB612, 0xC6B564, 0x17F250, 0xE41BC0, 0xAF8E27, 0x8E382E, 0x47A101, 0x9DAC33, 0x66F4CF, 0x59A9F0, 0x798D1A, 0x2EBB59, 0xBF66C3, 0x4BD8FB, 0xBBFA54, 0x6B9881, 0x144967, 0xBAA3AE, 0xE80B9D, 0x7BA552, 0x96A456, 0x17D7B4, 0x130C39, 0x3C06A8, 0x62737E, 0xA87E89, 0xB6D3E4, 0x66B77D, 0x66E304, 0x1B80E1, 0x7A06BC, 0xBFFB1B, 0x618506, 0x7E4D34};
long GetRandomColorByIndex(int index) {
    srand(index);
    int a = 255;
    int r = ((Colors[rand() % sizeof(Colors)] & 0xFF0000) >> 17);
    int g = ((Colors[rand() % sizeof(Colors)] & 0x00FF00) >> 9);
    int b = (Colors[rand() % sizeof(Colors)] & 0x0000FF);
    return IM_COL32(r, g, b, a);
}
long GetRandomColorByIndex2(int index) {
    srand(index);
    int a = 130;
    int r = ((Colors[rand() % sizeof(Colors)] & 0xFF0000) >> 17);
    int g = ((Colors[rand() % sizeof(Colors)] & 0x00FF00) >> 9);
    int b = (Colors[rand() % sizeof(Colors)] & 0x0000FF);
    return IM_COL32(r, g, b, a);
}
