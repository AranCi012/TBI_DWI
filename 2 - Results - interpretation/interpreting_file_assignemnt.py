import numpy as np

file_path = '/Users/emanueleamato/Downloads/test/sub-0001/assignments.csv'
output_path = '/Users/emanueleamato/Downloads/test/sub-0001/connectivity_matrix_from_assignments.csv'
zero_diagonal = True

# Leggi e filtra righe valide
clean_lines = []
with open(file_path, 'r') as f:
    for line in f:
        parts = line.strip().split()
        if len(parts) == 2 and parts[0].isdigit() and parts[1].isdigit():
            i, j = int(parts[0]), int(parts[1])
            clean_lines.append((i, j))

# Trova tutte le etichette uniche
all_labels = sorted(set(i for pair in clean_lines for i in pair))

# Crea mappatura: etichetta vera -> indice interno
label_to_index = {label: idx for idx, label in enumerate(all_labels)}
index_to_label = {idx: label for label, idx in label_to_index.items()}
n_labels = len(label_to_index)

# Inizializza matrice
connectivity_matrix = np.zeros((n_labels, n_labels), dtype=int)

# Popola matrice con mappatura
for i, j in clean_lines:
    i_mapped = label_to_index[i]
    j_mapped = label_to_index[j]
    connectivity_matrix[i_mapped, j_mapped] += 1

# Azzera diagonale se richiesto
if zero_diagonal:
    np.fill_diagonal(connectivity_matrix, 0)

# Salva
np.savetxt(output_path, connectivity_matrix, delimiter=',', fmt='%d')
print(f"✅ Matrice ({n_labels}x{n_labels}) generata da assignments.csv")
