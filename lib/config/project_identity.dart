abstract final class ProjectIdentity {
  static const college = 'Guru Nanak Dev Engineering College, Bidar';
  static const department = 'Computer Science & Engineering';
  static const guide = 'Prof. Gururaj S.';

  static const students = <ProjectStudent>[
    ProjectStudent(name: 'Ayesha', usn: '3GN23CS011'),
    ProjectStudent(name: 'Mahvin Ashfaque', usn: '3GN23CS035'),
    ProjectStudent(name: 'Iqra Mahveen', usn: '3GN23CS029'),
  ];
}

class ProjectStudent {
  const ProjectStudent({required this.name, required this.usn});

  final String name;
  final String usn;
}
