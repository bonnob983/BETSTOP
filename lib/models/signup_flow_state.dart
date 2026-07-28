import 'package:flutter/foundation.dart';

enum ExclusionType { full, partial }

class SignupFlowState extends ChangeNotifier {
  String? name;
  String? guardianName;
  String? phone;
  String? guardianPhone;
  String? commitmentLetter;
  ExclusionType? exclusionType;
  String? email;
  String? exclusionLetterFile;
  String? idCardFile;
  String? partialDuration; // '12h', '24h', '48h', '7d', '30d'

  void updateName(String value) {
    name = value;
    notifyListeners();
  }

  void updateGuardianName(String value) {
    guardianName = value;
    notifyListeners();
  }

  void updatePhone(String value) {
    phone = value;
    notifyListeners();
  }

  void updateGuardianPhone(String value) {
    guardianPhone = value;
    notifyListeners();
  }

  void updateCommitmentLetter(String value) {
    commitmentLetter = value;
    notifyListeners();
  }

  void updateExclusionType(ExclusionType value) {
    exclusionType = value;
    notifyListeners();
  }

  void updateEmail(String value) {
    email = value;
    notifyListeners();
  }

  void updateExclusionLetterFile(String value) {
    exclusionLetterFile = value;
    notifyListeners();
  }

  void updateIdCardFile(String value) {
    idCardFile = value;
    notifyListeners();
  }

  void updatePartialDuration(String value) {
    partialDuration = value;
    notifyListeners();
  }

  bool isSignupStep1Valid() {
    final phoneRegex = RegExp(r'^(?:\+254|0)7\d{8}$');
    return name != null &&
        name!.isNotEmpty &&
        guardianName != null &&
        guardianName!.isNotEmpty &&
        phone != null &&
        phoneRegex.hasMatch(phone!) &&
        guardianPhone != null &&
        phoneRegex.hasMatch(guardianPhone!) &&
        commitmentLetter != null &&
        commitmentLetter!.isNotEmpty;
  }

  bool isFullExclusionValid() {
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return email != null &&
        emailRegex.hasMatch(email!) &&
        exclusionLetterFile != null &&
        exclusionLetterFile!.isNotEmpty &&
        idCardFile != null &&
        idCardFile!.isNotEmpty;
  }

  bool isPartialExclusionValid() {
    return partialDuration != null && partialDuration!.isNotEmpty;
  }

  void reset() {
    name = null;
    guardianName = null;
    phone = null;
    guardianPhone = null;
    commitmentLetter = null;
    exclusionType = null;
    email = null;
    exclusionLetterFile = null;
    idCardFile = null;
    partialDuration = null;
    notifyListeners();
  }
}
